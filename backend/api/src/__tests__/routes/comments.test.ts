import * as reportModel from '../../models/report';
import * as commentModel from '../../models/comment';
import * as commentFlagModel from '../../models/comment-flag';
import * as deviceActivity from '../../models/device-activity';
import * as dbHealth from '../../lib/db';
import * as redisHealth from '../../lib/redis';

jest.mock('../../models/report');
jest.mock('../../models/comment');
jest.mock('../../models/comment-flag');
jest.mock('../../models/device-activity');
jest.mock('../../models/media');
jest.mock('../../models/report-upvote');
jest.mock('../../lib/db');
jest.mock('../../lib/redis');

const mockReport = reportModel as jest.Mocked<typeof reportModel>;
const mockComment = commentModel as jest.Mocked<typeof commentModel>;
const mockCommentFlag = commentFlagModel as jest.Mocked<typeof commentFlagModel>;
const mockDevice = deviceActivity as jest.Mocked<typeof deviceActivity>;
const mockDbHealth = dbHealth as jest.Mocked<typeof dbHealth>;
const mockRedisHealth = redisHealth as jest.Mocked<typeof redisHealth>;

import request from 'supertest';
import app from '../../app';

const REPORTS_BASE = '/api/v1/reports';
const COMMENTS_BASE = '/api/v1/comments';

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

const fakeComment = {
  id: 'c-1',
  report_id: 'r-123',
  device_id: 'device-2',
  content: 'Be careful around here',
  upvotes: 0,
  flag_count: 0,
  created_at: new Date('2025-01-01'),
};

const fakeDevice = {
  device_id: 'device-2',
  report_count_today: 0,
  last_report_at: null,
  flagged: false,
  created_at: new Date(),
};

beforeEach(() => {
  jest.clearAllMocks();
  mockDbHealth.checkHealth.mockResolvedValue(true);
  mockRedisHealth.checkHealth.mockResolvedValue(true);
});

// ────────────────────────────────────────────────
// GET /api/v1/reports/:id/comments
// ────────────────────────────────────────────────
describe('GET /api/v1/reports/:id/comments', () => {
  it('returns paginated comments for a report', async () => {
    mockReport.findById.mockResolvedValueOnce(fakeReport);
    mockComment.findByReportId.mockResolvedValueOnce([fakeComment]);

    const res = await request(app).get(`${REPORTS_BASE}/r-123/comments`);

    expect(res.status).toBe(200);
    expect(res.body.data).toHaveLength(1);
    expect(res.body.data[0].id).toBe('c-1');
    expect(res.body.meta).toEqual(
      expect.objectContaining({ report_id: 'r-123', limit: 20, offset: 0, count: 1 }),
    );
    expect(mockComment.findByReportId).toHaveBeenCalledWith('r-123', { limit: 20, offset: 0 });
  });

  it('applies custom pagination', async () => {
    mockReport.findById.mockResolvedValueOnce(fakeReport);
    mockComment.findByReportId.mockResolvedValueOnce([]);

    const res = await request(app)
      .get(`${REPORTS_BASE}/r-123/comments`)
      .query({ limit: 5, offset: 10 });

    expect(res.status).toBe(200);
    expect(mockComment.findByReportId).toHaveBeenCalledWith('r-123', { limit: 5, offset: 10 });
  });

  it('returns 404 when report does not exist', async () => {
    mockReport.findById.mockResolvedValueOnce(null);

    const res = await request(app).get(`${REPORTS_BASE}/nonexistent/comments`);

    expect(res.status).toBe(404);
    expect(res.body.error).toContain('not found');
  });
});

// ────────────────────────────────────────────────
// POST /api/v1/reports/:id/comments
// ────────────────────────────────────────────────
describe('POST /api/v1/reports/:id/comments', () => {
  const validBody = {
    device_id: 'device-2',
    content: 'Be careful around here',
  };

  it('creates a comment and returns 201', async () => {
    mockReport.findById.mockResolvedValueOnce(fakeReport);
    mockDevice.getOrCreate.mockResolvedValueOnce(fakeDevice);
    mockComment.countTodayByDevice.mockResolvedValueOnce(0);
    mockComment.createForReport.mockResolvedValueOnce(fakeComment);

    const res = await request(app).post(`${REPORTS_BASE}/r-123/comments`).send(validBody);

    expect(res.status).toBe(201);
    expect(res.body.id).toBe('c-1');
    expect(res.body.content).toBe('Be careful around here');
    expect(mockComment.createForReport).toHaveBeenCalledWith({
      report_id: 'r-123',
      device_id: 'device-2',
      content: 'Be careful around here',
    });
  });

  it('returns 404 when report does not exist', async () => {
    mockReport.findById.mockResolvedValueOnce(null);

    const res = await request(app).post(`${REPORTS_BASE}/nonexistent/comments`).send(validBody);

    expect(res.status).toBe(404);
    expect(res.body.error).toContain('not found');
  });

  it('returns 403 when report is removed', async () => {
    mockReport.findById.mockResolvedValueOnce({ ...fakeReport, status: 'removed' });

    const res = await request(app).post(`${REPORTS_BASE}/r-123/comments`).send(validBody);

    expect(res.status).toBe(403);
    expect(res.body.error).toContain('removed');
  });

  it('returns 403 when device is flagged', async () => {
    mockReport.findById.mockResolvedValueOnce(fakeReport);
    mockDevice.getOrCreate.mockResolvedValueOnce({ ...fakeDevice, flagged: true });

    const res = await request(app).post(`${REPORTS_BASE}/r-123/comments`).send(validBody);

    expect(res.status).toBe(403);
    expect(res.body.error).toContain('flagged');
  });

  it('returns 429 when daily comment limit is exceeded', async () => {
    mockReport.findById.mockResolvedValueOnce(fakeReport);
    mockDevice.getOrCreate.mockResolvedValueOnce(fakeDevice);
    mockComment.countTodayByDevice.mockResolvedValueOnce(50);

    const res = await request(app).post(`${REPORTS_BASE}/r-123/comments`).send(validBody);

    expect(res.status).toBe(429);
    expect(res.body.error).toContain('limit');
  });

  it('returns 400 when content is missing', async () => {
    const res = await request(app)
      .post(`${REPORTS_BASE}/r-123/comments`)
      .send({ device_id: 'device-2' });

    expect(res.status).toBe(400);
    expect(res.body.error).toBe('Validation failed');
    expect(res.body.details).toEqual(
      expect.arrayContaining([expect.objectContaining({ field: 'content' })]),
    );
  });

  it('returns 400 when device_id is missing', async () => {
    const res = await request(app)
      .post(`${REPORTS_BASE}/r-123/comments`)
      .send({ content: 'Hello' });

    expect(res.status).toBe(400);
    expect(res.body.error).toBe('Validation failed');
    expect(res.body.details).toEqual(
      expect.arrayContaining([expect.objectContaining({ field: 'device_id' })]),
    );
  });

  it('returns 400 when content exceeds 1000 chars', async () => {
    const res = await request(app)
      .post(`${REPORTS_BASE}/r-123/comments`)
      .send({ device_id: 'device-2', content: 'x'.repeat(1001) });

    expect(res.status).toBe(400);
    expect(res.body.details).toEqual(
      expect.arrayContaining([expect.objectContaining({ field: 'content' })]),
    );
  });

  it('returns 400 when content is whitespace only', async () => {
    const res = await request(app)
      .post(`${REPORTS_BASE}/r-123/comments`)
      .send({ device_id: 'device-2', content: '   ' });

    expect(res.status).toBe(400);
    expect(res.body.details).toEqual(
      expect.arrayContaining([expect.objectContaining({ field: 'content' })]),
    );
  });
});

// ────────────────────────────────────────────────
// POST /api/v1/comments/:id/flag
// ────────────────────────────────────────────────
describe('POST /api/v1/comments/:id/flag', () => {
  const validBody = { device_id: 'device-3' };

  it('flags a comment and returns flagged: true', async () => {
    mockComment.findById.mockResolvedValueOnce(fakeComment);
    mockCommentFlag.flag.mockResolvedValueOnce(true);

    const res = await request(app).post(`${COMMENTS_BASE}/c-1/flag`).send(validBody);

    expect(res.status).toBe(200);
    expect(res.body.flagged).toBe(true);
    expect(mockCommentFlag.flag).toHaveBeenCalledWith('c-1', 'device-3');
  });

  it('returns flagged: false when already flagged by this device', async () => {
    mockComment.findById.mockResolvedValueOnce(fakeComment);
    mockCommentFlag.flag.mockResolvedValueOnce(false);

    const res = await request(app).post(`${COMMENTS_BASE}/c-1/flag`).send(validBody);

    expect(res.status).toBe(200);
    expect(res.body.flagged).toBe(false);
  });

  it('returns 404 when comment does not exist', async () => {
    mockComment.findById.mockResolvedValueOnce(null);

    const res = await request(app).post(`${COMMENTS_BASE}/nonexistent/flag`).send(validBody);

    expect(res.status).toBe(404);
    expect(res.body.error).toContain('not found');
  });

  it('returns 400 when device_id is missing', async () => {
    const res = await request(app).post(`${COMMENTS_BASE}/c-1/flag`).send({});

    expect(res.status).toBe(400);
    expect(res.body.error).toBe('Validation failed');
  });
});
