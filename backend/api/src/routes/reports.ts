import { Router, Request, Response } from 'express';
import { validate } from '../middleware/validate';
import { createReportSchema, nearbyQuerySchema, upvoteSchema } from '../validators/report';
import { HttpError } from '../lib/errors';
import * as reportModel from '../models/report';
import * as mediaModel from '../models/media';
import * as upvoteModel from '../models/report-upvote';
import * as deviceActivity from '../models/device-activity';

const MAX_DAILY_REPORTS = 10;

const router = Router();

router.post('/', validate(createReportSchema), async (req: Request, res: Response) => {
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

router.post('/:id/upvote', validate(upvoteSchema), async (req: Request, res: Response) => {
  const { id } = req.params;
  const { device_id } = req.body;

  const report = await reportModel.findById(id);
  if (!report) {
    throw HttpError.notFound('Report not found');
  }

  const upvoted = await upvoteModel.toggle(id, device_id);

  res.json({ upvoted });
});

export default router;
