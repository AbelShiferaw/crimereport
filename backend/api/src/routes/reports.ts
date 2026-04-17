import { randomUUID } from 'crypto';
import { Router, Request, Response } from 'express';
import { validate } from '../middleware/validate';
import { writeLimiter } from '../middleware/rate-limit';
import { createReportSchema, nearbyQuerySchema, upvoteSchema } from '../validators/report';
import { createCommentSchema, commentListQuerySchema } from '../validators/comment';
import { uploadRequestSchema, uploadCompleteSchema } from '../validators/media';
import { HttpError } from '../lib/errors';
import { config } from '../config';
import * as s3 from '../lib/s3';
import * as broadcast from '../lib/broadcast';
import * as reportModel from '../models/report';
import * as mediaModel from '../models/media';
import * as commentModel from '../models/comment';
import * as upvoteModel from '../models/report-upvote';
import * as deviceActivity from '../models/device-activity';
import * as pushModel from '../models/push-subscription';
import * as sns from '../lib/sns';
import * as metrics from '../lib/metrics';
import { logger } from '../lib/logger';

const MAX_DAILY_REPORTS = 10;
const MAX_DAILY_COMMENTS = 50;
const MAX_MEDIA_PER_REPORT = 5;

const router = Router();

router.post('/', writeLimiter, validate(createReportSchema), async (req: Request, res: Response) => {
  const { device_id, type, description, lat, lng, address } = req.body;

  const device = await deviceActivity.getOrCreate(device_id);

  if (device.flagged) {
    throw HttpError.forbidden('This device has been flagged for abuse');
  }

  if (device.report_count_today >= MAX_DAILY_REPORTS) {
    throw HttpError.tooManyRequests(`Daily report limit of ${MAX_DAILY_REPORTS} reached`);
  }

  const report = await reportModel.create({ device_id, type, description, lat, lng, address });
  await deviceActivity.incrementReportCount(device_id);

  metrics.recordReportCreated(type).catch((err) =>
    logger.warn({ err }, 'failed to record ReportsCreated metric'),
  );

  res.status(201).json(report);
});

router.get('/', validate(nearbyQuerySchema, 'query'), async (req: Request, res: Response) => {
  const { lat, lng, radius, limit, offset } = req.query as unknown as {
    lat: number;
    lng: number;
    radius: number;
    limit: number;
    offset: number;
  };

  const reports = await reportModel.findNearby(lat, lng, radius, { limit, offset });

  res.json({ data: reports, meta: { lat, lng, radius, limit, offset, count: reports.length } });
});

router.get('/:id', async (req: Request, res: Response) => {
  const report = await reportModel.findById(req.params.id);

  if (!report) {
    throw HttpError.notFound('Report not found');
  }

  const media = await mediaModel.findByReportId(report.id);

  res.json({ ...report, media });
});

router.post('/:id/upvote', writeLimiter, validate(upvoteSchema), async (req: Request, res: Response) => {
  const { id } = req.params;
  const { device_id } = req.body;

  const report = await reportModel.findById(id);
  if (!report) {
    throw HttpError.notFound('Report not found');
  }

  const upvoted = await upvoteModel.toggle(id, device_id);

  broadcast.broadcastUpvote(id, upvoted);

  res.json({ upvoted });
});

// ────────────────────────────────────────────────
// Comments sub-routes (nested under /reports/:id)
// ────────────────────────────────────────────────

router.get(
  '/:id/comments',
  validate(commentListQuerySchema, 'query'),
  async (req: Request, res: Response) => {
    const { id } = req.params;
    const { limit, offset } = req.query as unknown as { limit: number; offset: number };

    const report = await reportModel.findById(id);
    if (!report) {
      throw HttpError.notFound('Report not found');
    }

    const comments = await commentModel.findByReportId(id, { limit, offset });

    res.json({ data: comments, meta: { report_id: id, limit, offset, count: comments.length } });
  },
);

router.post(
  '/:id/comments',
  writeLimiter,
  validate(createCommentSchema),
  async (req: Request, res: Response) => {
    const { id } = req.params;
    const { device_id, content } = req.body;

    const report = await reportModel.findById(id);
    if (!report) {
      throw HttpError.notFound('Report not found');
    }

    if (report.status === 'removed') {
      throw HttpError.forbidden('Cannot comment on a removed report');
    }

    const device = await deviceActivity.getOrCreate(device_id);
    if (device.flagged) {
      throw HttpError.forbidden('This device has been flagged for abuse');
    }

    const todayCount = await commentModel.countTodayByDevice(device_id);
    if (todayCount >= MAX_DAILY_COMMENTS) {
      throw HttpError.tooManyRequests(`Daily comment limit of ${MAX_DAILY_COMMENTS} reached`);
    }

    const comment = await commentModel.createForReport({ report_id: id, device_id, content });

    broadcast.broadcastNewComment(comment);

    res.status(201).json(comment);
  },
);

// ────────────────────────────────────────────────
// Media upload sub-routes (nested under /reports/:id)
// ────────────────────────────────────────────────

const CONTENT_TYPE_TO_EXT: Record<string, string> = {
  'image/jpeg': 'jpg',
  'image/png': 'png',
  'image/webp': 'webp',
  'video/mp4': 'mp4',
  'video/quicktime': 'mov',
  'video/webm': 'webm',
};

const UPLOAD_ALLOWED_STATUSES = new Set(['pending', 'uploading', 'failed']);

router.post(
  '/:id/upload',
  writeLimiter,
  validate(uploadRequestSchema),
  async (req: Request, res: Response) => {
    const { id } = req.params;
    const { device_id, file_type, content_type } = req.body;

    const report = await reportModel.findById(id);
    if (!report) {
      throw HttpError.notFound('Report not found');
    }

    if (report.device_id !== device_id) {
      throw HttpError.forbidden('Not authorized to upload to this report');
    }

    if (report.status === 'removed') {
      throw HttpError.forbidden('Cannot upload to a removed report');
    }

    if (!UPLOAD_ALLOWED_STATUSES.has(report.status)) {
      throw HttpError.conflict('Report already has media being processed or active');
    }

    const device = await deviceActivity.getOrCreate(device_id);
    if (device.flagged) {
      throw HttpError.forbidden('This device has been flagged for abuse');
    }

    const existingMedia = await mediaModel.findByReportId(id);
    if (existingMedia.length >= MAX_MEDIA_PER_REPORT) {
      throw HttpError.badRequest(`Maximum of ${MAX_MEDIA_PER_REPORT} media items per report`);
    }

    const ext = CONTENT_TYPE_TO_EXT[content_type] ?? 'bin';
    const fileId = randomUUID();
    const mediaKey = s3.buildMediaKey(file_type, id, fileId, ext);

    const { url: uploadUrl, expiresIn } = await s3.generateUploadUrl(mediaKey, content_type);

    await mediaModel.create({
      report_id: id,
      type: file_type,
      url: '',
      media_key: mediaKey,
    });

    await reportModel.updateStatus(id, 'uploading');

    res.status(201).json({ upload_url: uploadUrl, media_key: mediaKey, expires_in: expiresIn });
  },
);

router.post(
  '/:id/upload/complete',
  writeLimiter,
  validate(uploadCompleteSchema),
  async (req: Request, res: Response) => {
    const { id } = req.params;
    const { device_id, media_key } = req.body;

    const report = await reportModel.findById(id);
    if (!report) {
      throw HttpError.notFound('Report not found');
    }

    if (report.device_id !== device_id) {
      throw HttpError.forbidden('Not authorized for this report');
    }

    const media = await mediaModel.findByMediaKey(media_key);
    if (!media || media.report_id !== id) {
      throw HttpError.notFound('Media not found for this report');
    }

    if (media.status === 'processing' || media.status === 'active') {
      res.json({ status: media.status });
      return;
    }

    const exists = await s3.objectExists(config.aws.s3UploadsBucket, media_key);
    if (!exists) {
      throw HttpError.badRequest('File not found in uploads bucket. Upload may have failed.');
    }

    await mediaModel.updateStatus(media_key, 'processing');
    await reportModel.updateStatus(id, 'processing');

    res.json({ status: 'processing' });
  },
);

router.get('/:id/media/status', async (req: Request, res: Response) => {
  const { id } = req.params;

  const report = await reportModel.findById(id);
  if (!report) {
    throw HttpError.notFound('Report not found');
  }

  const mediaItems = await mediaModel.findByReportId(id);

  if (mediaItems.length === 0) {
    res.json({ status: report.status, media: [] });
    return;
  }

  const results = await Promise.all(
    mediaItems.map(async (item) => {
      if (item.status === 'active') return item;
      if (!item.media_key) return item;

      const processedKey = item.media_key;
      const processed = await s3.objectExists(config.aws.s3MediaBucket, processedKey);

      if (processed) {
        const cdnUrl = s3.buildCdnUrl(processedKey);

        const thumbnailKey = processedKey.replace(/\.[^.]+$/, '_thumb.jpg');
        const hasThumb = await s3.objectExists(config.aws.s3MediaBucket, thumbnailKey);
        const thumbUrl = hasThumb ? s3.buildCdnUrl(thumbnailKey) : null;

        const updated = await mediaModel.updateUrls(processedKey, cdnUrl, thumbUrl);
        return updated ?? item;
      }

      const stillInUploads = await s3.objectExists(config.aws.s3UploadsBucket, processedKey);
      if (!stillInUploads && item.status === 'processing') {
        await mediaModel.updateStatus(processedKey, 'failed');
        return { ...item, status: 'failed' };
      }

      return item;
    }),
  );

  const allActive = results.every((m) => m.status === 'active');
  const anyFailed = results.some((m) => m.status === 'failed');

  if (allActive && report.status !== 'active') {
    const updatedReport = await reportModel.updateStatus(id, 'active');
    if (updatedReport) {
      broadcast.broadcastNewReport(updatedReport);
      sendNearbyNotifications(updatedReport).catch((err) =>
        logger.error({ err, reportId: updatedReport.id }, 'push notification batch failed'),
      );
      metrics.recordMediaUploadCompleted().catch((err) =>
        logger.warn({ err }, 'failed to record MediaUploadsCompleted metric'),
      );
      const durationMs = Date.now() - new Date(report.created_at).getTime();
      metrics.recordMediaProcessingLatency(durationMs).catch((err) =>
        logger.warn({ err }, 'failed to record MediaProcessingLatency metric'),
      );
    }
  } else if (anyFailed && report.status === 'processing') {
    await reportModel.updateStatus(id, 'failed');
    metrics.recordMediaFailure().catch((err) =>
      logger.warn({ err }, 'failed to record MediaFailureRate metric'),
    );
  }

  const currentStatus = allActive ? 'active' : anyFailed ? 'failed' : report.status;

  res.json({ status: currentStatus, media: results });
});

async function sendNearbyNotifications(report: {
  id: string;
  device_id: string;
  type: string;
  description: string | null;
  lat: number;
  lng: number;
}) {
  const devices = await pushModel.findNearbyEnabled(
    report.lat,
    report.lng,
    report.type,
    report.device_id,
  );

  if (devices.length === 0) return;
  logger.info({ reportId: report.id, deviceCount: devices.length }, 'sending push notifications');

  const typeLabel =
    report.type.charAt(0).toUpperCase() + report.type.slice(1).replace('_', ' ');
  const notification = {
    title: `${typeLabel} Reported Nearby`,
    body: report.description?.substring(0, 100) || 'A new crime was reported in your area',
    data: {
      report_id: report.id,
      type: report.type,
      lat: String(report.lat),
      lng: String(report.lng),
    },
  };

  const results = await Promise.allSettled(
    devices.map(async (device) => {
      const ok = await sns.sendToDevice(device.endpoint_arn!, device.platform, notification);
      if (!ok && device.endpoint_arn) {
        await pushModel.disableByEndpointArn(device.endpoint_arn);
      }
    }),
  );

  const failed = results.filter((r) => r.status === 'rejected').length;
  if (failed > 0) {
    logger.warn({ reportId: report.id, failed, total: devices.length }, 'some push sends failed');
  }
}

export default router;
