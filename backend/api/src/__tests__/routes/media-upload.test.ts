import * as reportModel from '../../models/report';
import * as mediaModel from '../../models/media';
import * as deviceActivity from '../../models/device-activity';
import * as s3Lib from '../../lib/s3';
import * as dbHealth from '../../lib/db';
import * as redisHealth from '../../lib/redis';

jest.mock('../../models/report');
jest.mock('../../models/media');
jest.mock('../../models/device-activity');
jest.mock('../../lib/s3');
jest.mock('../../lib/db');
jest.mock('../../lib/redis');
jest.mock('../../lib/broadcast');
jest.mock('../../lib/socket');

const mockReport = reportModel as jest.Mocked<typeof reportModel>;
const mockMedia = mediaModel as jest.Mocked<typeof mediaModel>;
const mockDevice = deviceActivity as jest.Mocked<typeof deviceActivity>;
const mockS3 = s3Lib as jest.Mocked<typeof s3Lib>;
const mockDbHealth = dbHealth as jest.Mocked<typeof dbHealth>;
const mockRedisHealth = redisHealth as jest.Mocked<typeof redisHealth>;

import request from 'supertest';
import app from '../../app';

const BASE = '/api/v1/reports';

const fakeReport = {
  id: 'r-123',
  device_id: 'device-1',
  type: 'theft',
  description: 'Stolen bike',
  lat: 40.7128,
  lng: -74.006,
  address: '123 Main St',
  status: 'pending',
  upvotes: 0,
  comment_count: 0,
  created_at: new Date('2025-01-01'),
  updated_at: new Date('2025-01-01'),
};

const fakeDevice = {
  device_id: 'device-1',
  report_count_today: 0,
  last_report_at: null,
  flagged: false,
  created_at: new Date(),
};

const fakeMedia = {
  id: 'm-1',
  report_id: 'r-123',
  type: 'image' as const,
  url: '',
  thumbnail_url: null,
  media_key: 'images/r-123/file-1.jpg',
  status: 'pending',
  failure_reason: null,
  duration_ms: null,
  width: null,
  height: null,
  created_at: new Date(),
};

beforeEach(() => {
  jest.clearAllMocks();
  mockDbHealth.checkHealth.mockResolvedValue(true);
  mockRedisHealth.checkHealth.mockResolvedValue(true);
});

// ────────────────────────────────────────────────
// POST /api/v1/reports/:id/upload
// ────────────────────────────────────────────────
describe('POST /api/v1/reports/:id/upload', () => {
  const validBody = {
    device_id: 'device-1',
    file_type: 'image',
    content_type: 'image/jpeg',
  };

  it('returns presigned URL and media_key', async () => {
    mockReport.findById.mockResolvedValueOnce(fakeReport);
    mockDevice.getOrCreate.mockResolvedValueOnce(fakeDevice);
    mockMedia.findByReportId.mockResolvedValueOnce([]);
    mockS3.buildMediaKey.mockReturnValueOnce('images/r-123/some-uuid.jpg');
    mockS3.generateUploadUrl.mockResolvedValueOnce({
      url: 'https://s3.presigned.url',
      expiresIn: 900,
    });
    mockMedia.create.mockResolvedValueOnce(fakeMedia);
    mockReport.updateStatus.mockResolvedValueOnce({ ...fakeReport, status: 'uploading' });

    const res = await request(app).post(`${BASE}/r-123/upload`).send(validBody);

    expect(res.status).toBe(201);
    expect(res.body.upload_url).toBe('https://s3.presigned.url');
    expect(res.body.media_key).toBe('images/r-123/some-uuid.jpg');
    expect(res.body.expires_in).toBe(900);
    expect(mockMedia.create).toHaveBeenCalledWith(
      expect.objectContaining({ report_id: 'r-123', type: 'image', media_key: 'images/r-123/some-uuid.jpg' }),
    );
  });

  it('returns 404 if report does not exist', async () => {
    mockReport.findById.mockResolvedValueOnce(null);

    const res = await request(app).post(`${BASE}/nonexistent/upload`).send(validBody);

    expect(res.status).toBe(404);
  });

  it('returns 403 if device_id does not match report owner', async () => {
    mockReport.findById.mockResolvedValueOnce({ ...fakeReport, device_id: 'other-device' });

    const res = await request(app).post(`${BASE}/r-123/upload`).send(validBody);

    expect(res.status).toBe(403);
    expect(res.body.error).toContain('Not authorized');
  });

  it('returns 403 if report is removed', async () => {
    mockReport.findById.mockResolvedValueOnce({ ...fakeReport, status: 'removed' });

    const res = await request(app).post(`${BASE}/r-123/upload`).send(validBody);

    expect(res.status).toBe(403);
    expect(res.body.error).toContain('removed');
  });

  it('returns 409 if report is already processing or active', async () => {
    mockReport.findById.mockResolvedValueOnce({ ...fakeReport, status: 'processing' });

    const res = await request(app).post(`${BASE}/r-123/upload`).send(validBody);

    expect(res.status).toBe(409);
    expect(res.body.error).toContain('already has media');
  });

  it('returns 403 if device is flagged', async () => {
    mockReport.findById.mockResolvedValueOnce(fakeReport);
    mockDevice.getOrCreate.mockResolvedValueOnce({ ...fakeDevice, flagged: true });

    const res = await request(app).post(`${BASE}/r-123/upload`).send(validBody);

    expect(res.status).toBe(403);
    expect(res.body.error).toContain('flagged');
  });

  it('returns 400 when media limit per report is exceeded', async () => {
    mockReport.findById.mockResolvedValueOnce(fakeReport);
    mockDevice.getOrCreate.mockResolvedValueOnce(fakeDevice);
    mockMedia.findByReportId.mockResolvedValueOnce(
      Array.from({ length: 5 }, (_, i) => ({ ...fakeMedia, id: `m-${i}` })),
    );

    const res = await request(app).post(`${BASE}/r-123/upload`).send(validBody);

    expect(res.status).toBe(400);
    expect(res.body.error).toContain('Maximum');
  });

  it('returns 400 when content_type does not match file_type', async () => {
    const res = await request(app).post(`${BASE}/r-123/upload`).send({
      device_id: 'device-1',
      file_type: 'image',
      content_type: 'video/mp4',
    });

    expect(res.status).toBe(400);
  });

  it('returns 400 when required fields are missing', async () => {
    const res = await request(app).post(`${BASE}/r-123/upload`).send({ device_id: 'device-1' });

    expect(res.status).toBe(400);
  });
});

// ────────────────────────────────────────────────
// POST /api/v1/reports/:id/upload/complete
// ────────────────────────────────────────────────
describe('POST /api/v1/reports/:id/upload/complete', () => {
  const validBody = {
    device_id: 'device-1',
    media_key: 'images/r-123/file-1.jpg',
  };

  it('marks media as processing when upload confirmed', async () => {
    mockReport.findById.mockResolvedValueOnce(fakeReport);
    mockMedia.findByMediaKey.mockResolvedValueOnce(fakeMedia);
    mockS3.objectExists.mockResolvedValueOnce(true);
    mockMedia.updateStatus.mockResolvedValueOnce(undefined);
    mockReport.updateStatus.mockResolvedValueOnce({ ...fakeReport, status: 'processing' });

    const res = await request(app).post(`${BASE}/r-123/upload/complete`).send(validBody);

    expect(res.status).toBe(200);
    expect(res.body.status).toBe('processing');
    expect(mockMedia.updateStatus).toHaveBeenCalledWith('images/r-123/file-1.jpg', 'processing');
    expect(mockReport.updateStatus).toHaveBeenCalledWith('r-123', 'processing');
  });

  it('returns 404 if report does not exist', async () => {
    mockReport.findById.mockResolvedValueOnce(null);

    const res = await request(app).post(`${BASE}/r-123/upload/complete`).send(validBody);

    expect(res.status).toBe(404);
  });

  it('returns 403 if device does not own the report', async () => {
    mockReport.findById.mockResolvedValueOnce({ ...fakeReport, device_id: 'other-device' });

    const res = await request(app).post(`${BASE}/r-123/upload/complete`).send(validBody);

    expect(res.status).toBe(403);
  });

  it('returns 404 if media_key not found for report', async () => {
    mockReport.findById.mockResolvedValueOnce(fakeReport);
    mockMedia.findByMediaKey.mockResolvedValueOnce(null);

    const res = await request(app).post(`${BASE}/r-123/upload/complete`).send(validBody);

    expect(res.status).toBe(404);
  });

  it('returns 400 if file not in S3', async () => {
    mockReport.findById.mockResolvedValueOnce(fakeReport);
    mockMedia.findByMediaKey.mockResolvedValueOnce(fakeMedia);
    mockS3.objectExists.mockResolvedValueOnce(false);

    const res = await request(app).post(`${BASE}/r-123/upload/complete`).send(validBody);

    expect(res.status).toBe(400);
    expect(res.body.error).toContain('not found');
  });

  it('is idempotent when media already processing', async () => {
    mockReport.findById.mockResolvedValueOnce(fakeReport);
    mockMedia.findByMediaKey.mockResolvedValueOnce({ ...fakeMedia, status: 'processing' });

    const res = await request(app).post(`${BASE}/r-123/upload/complete`).send(validBody);

    expect(res.status).toBe(200);
    expect(res.body.status).toBe('processing');
    expect(mockS3.objectExists).not.toHaveBeenCalled();
  });

  it('is idempotent when media already active', async () => {
    mockReport.findById.mockResolvedValueOnce(fakeReport);
    mockMedia.findByMediaKey.mockResolvedValueOnce({ ...fakeMedia, status: 'active' });

    const res = await request(app).post(`${BASE}/r-123/upload/complete`).send(validBody);

    expect(res.status).toBe(200);
    expect(res.body.status).toBe('active');
    expect(mockS3.objectExists).not.toHaveBeenCalled();
  });
});

// ────────────────────────────────────────────────
// GET /api/v1/reports/:id/media/status
// ────────────────────────────────────────────────
describe('GET /api/v1/reports/:id/media/status', () => {
  it('returns empty media array when no media exists', async () => {
    mockReport.findById.mockResolvedValueOnce(fakeReport);
    mockMedia.findByReportId.mockResolvedValueOnce([]);

    const res = await request(app).get(`${BASE}/r-123/media/status`);

    expect(res.status).toBe(200);
    expect(res.body.status).toBe('pending');
    expect(res.body.media).toEqual([]);
  });

  it('returns active media with CDN urls when processing is done', async () => {
    const processingMedia = { ...fakeMedia, status: 'processing' };
    const updatedMedia = { ...fakeMedia, status: 'active', url: 'https://cdn/images/r-123/file-1.jpg' };

    mockReport.findById.mockResolvedValueOnce({ ...fakeReport, status: 'processing' });
    mockMedia.findByReportId.mockResolvedValueOnce([processingMedia]);
    mockS3.objectExists
      .mockResolvedValueOnce(true)   // processed media exists
      .mockResolvedValueOnce(false); // thumbnail doesn't exist
    mockS3.buildCdnUrl.mockReturnValueOnce('https://cdn/images/r-123/file-1.jpg');
    mockMedia.updateUrls.mockResolvedValueOnce(updatedMedia);
    mockReport.updateStatus.mockResolvedValueOnce({ ...fakeReport, status: 'active' });

    const res = await request(app).get(`${BASE}/r-123/media/status`);

    expect(res.status).toBe(200);
    expect(res.body.status).toBe('active');
    expect(res.body.media).toHaveLength(1);
    expect(res.body.media[0].status).toBe('active');
  });

  it('marks media as failed (flagged_content) when file vanishes from both buckets', async () => {
    const processingMedia = { ...fakeMedia, status: 'processing' };

    mockReport.findById.mockResolvedValueOnce({ ...fakeReport, status: 'processing' });
    mockMedia.findByReportId.mockResolvedValueOnce([processingMedia]);
    mockS3.objectExists
      .mockResolvedValueOnce(false)  // not in processed bucket
      .mockResolvedValueOnce(false); // not in uploads bucket either
    mockMedia.updateFailure.mockResolvedValueOnce(undefined);
    mockReport.updateStatus.mockResolvedValueOnce({ ...fakeReport, status: 'failed' });

    const res = await request(app).get(`${BASE}/r-123/media/status`);

    expect(res.status).toBe(200);
    expect(res.body.status).toBe('failed');
    expect(res.body.media[0].status).toBe('failed');
    expect(res.body.media[0].failure_reason).toBe('flagged_content');
    expect(mockMedia.updateFailure).toHaveBeenCalledWith(
      'images/r-123/file-1.jpg',
      'flagged_content',
    );
  });

  it('preserves processing_error failure_reason set by the pipeline', async () => {
    // Simulate the case where the Step Functions pipeline marked the
    // media as failed with `processing_error` (e.g. unsupported codec)
    // but left the upload in S3. The route should NOT re-classify it as
    // flagged_content.
    const failedMedia = {
      ...fakeMedia,
      status: 'failed',
      failure_reason: 'processing_error' as const,
    };

    mockReport.findById.mockResolvedValueOnce({ ...fakeReport, status: 'processing' });
    mockMedia.findByReportId.mockResolvedValueOnce([failedMedia]);
    mockS3.objectExists
      .mockResolvedValueOnce(false) // not in processed bucket
      .mockResolvedValueOnce(true); // still in uploads bucket
    mockReport.updateStatus.mockResolvedValueOnce({ ...fakeReport, status: 'failed' });

    const res = await request(app).get(`${BASE}/r-123/media/status`);

    expect(res.status).toBe(200);
    expect(res.body.status).toBe('failed');
    expect(res.body.media[0].failure_reason).toBe('processing_error');
    expect(mockMedia.updateFailure).not.toHaveBeenCalled();
  });

  it('returns 404 if report does not exist', async () => {
    mockReport.findById.mockResolvedValueOnce(null);

    const res = await request(app).get(`${BASE}/nonexistent/media/status`);

    expect(res.status).toBe(404);
  });
});

describe('POST /api/v1/reports/:id/upload — extended', () => {
  const validBody = { device_id: 'device-1', file_type: 'image', content_type: 'image/jpeg' };
  it('returns 400 when report already has 5 media items', async () => {
    mockReport.findById.mockResolvedValueOnce(fakeReport);
    mockDevice.getOrCreate.mockResolvedValueOnce(fakeDevice);
    mockMedia.findByReportId.mockResolvedValueOnce(Array.from({ length: 5 }, (_, i) => ({ ...fakeMedia, id: `m-${i}` })));
    const res = await request(app).post(`${BASE}/r-123/upload`).send(validBody);
    expect(res.status).toBe(400);
  });
  it('returns 403 for removed report', async () => {
    mockReport.findById.mockResolvedValueOnce({ ...fakeReport, status: 'removed' });
    const res = await request(app).post(`${BASE}/r-123/upload`).send(validBody);
    expect(res.status).toBe(403);
  });
});

describe('POST /api/v1/reports/:id/upload/complete — extended', () => {
  it('returns 400 when file not in S3', async () => {
    mockReport.findById.mockResolvedValueOnce(fakeReport);
    mockMedia.findByMediaKey.mockResolvedValueOnce(fakeMedia);
    mockS3.objectExists.mockResolvedValueOnce(false);
    const res = await request(app).post(`${BASE}/r-123/upload/complete`).send({ device_id: 'device-1', media_key: 'images/r-123/file-1.jpg' });
    expect(res.status).toBe(400);
  });
});

describe('GET /api/v1/reports/:id/media/status — extended', () => {
  it('returns empty array for report with no media', async () => {
    mockReport.findById.mockResolvedValueOnce(fakeReport);
    mockMedia.findByReportId.mockResolvedValueOnce([]);
    const res = await request(app).get(`${BASE}/r-123/media/status`);
    expect(res.status).toBe(200);
    expect(res.body.media).toEqual([]);
  });
});
