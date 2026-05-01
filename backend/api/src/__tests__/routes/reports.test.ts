import * as reportModel from '../../models/report';
import * as mediaModel from '../../models/media';
import * as upvoteModel from '../../models/report-upvote';
import * as deviceActivity from '../../models/device-activity';
import * as dbHealth from '../../lib/db';
import * as redisHealth from '../../lib/redis';
import * as broadcastMod from '../../lib/broadcast';

jest.mock('../../models/report');
jest.mock('../../models/media');
jest.mock('../../models/report-upvote');
jest.mock('../../models/device-activity');
jest.mock('../../lib/db');
jest.mock('../../lib/redis');
jest.mock('../../lib/broadcast');
jest.mock('../../lib/socket');

const mockReport = reportModel as jest.Mocked<typeof reportModel>;
const mockMedia = mediaModel as jest.Mocked<typeof mediaModel>;
const mockUpvote = upvoteModel as jest.Mocked<typeof upvoteModel>;
const mockDevice = deviceActivity as jest.Mocked<typeof deviceActivity>;
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

beforeEach(() => {
  jest.clearAllMocks();
  mockDbHealth.checkHealth.mockResolvedValue(true);
  mockRedisHealth.checkHealth.mockResolvedValue(true);
});

// ────────────────────────────────────────────────
// POST /api/v1/reports
// ────────────────────────────────────────────────
describe('POST /api/v1/reports', () => {
  const validBody = {
    device_id: 'device-1',
    type: 'theft',
    description: 'Stolen bike',
    lat: 40.7128,
    lng: -74.006,
    address: '123 Main St',
  };

  it('creates a report and returns 201', async () => {
    mockDevice.getOrCreate.mockResolvedValueOnce(fakeDevice);
    mockReport.create.mockResolvedValueOnce(fakeReport);
    mockDevice.incrementReportCount.mockResolvedValueOnce({ ...fakeDevice, report_count_today: 1 });

    const res = await request(app).post(BASE).send(validBody);

    expect(res.status).toBe(201);
    expect(res.body.id).toBe('r-123');
    expect(mockReport.create).toHaveBeenCalledWith(
      expect.objectContaining({ device_id: 'device-1', type: 'theft' }),
    );
    expect(mockDevice.incrementReportCount).toHaveBeenCalledWith('device-1');
  });

  it('returns 400 when required fields are missing', async () => {
    const res = await request(app).post(BASE).send({ device_id: 'device-1' });

    expect(res.status).toBe(400);
    expect(res.body.error).toBe('Validation failed');
    expect(res.body.details).toEqual(
      expect.arrayContaining([expect.objectContaining({ field: 'type' })]),
    );
  });

  it('returns 400 when lat is out of range', async () => {
    const res = await request(app).post(BASE).send({ ...validBody, lat: 999 });

    expect(res.status).toBe(400);
    expect(res.body.details).toEqual(
      expect.arrayContaining([expect.objectContaining({ field: 'lat' })]),
    );
  });

  it('returns 400 for invalid crime type', async () => {
    const res = await request(app).post(BASE).send({ ...validBody, type: 'not-a-crime' });

    expect(res.status).toBe(400);
    expect(res.body.details).toEqual(
      expect.arrayContaining([expect.objectContaining({ field: 'type' })]),
    );
  });

  it('returns 403 when device is flagged', async () => {
    mockDevice.getOrCreate.mockResolvedValueOnce({ ...fakeDevice, flagged: true });

    const res = await request(app).post(BASE).send(validBody);

    expect(res.status).toBe(403);
    expect(res.body.error).toContain('flagged');
  });

  it('returns 429 when daily limit is exceeded', async () => {
    mockDevice.getOrCreate.mockResolvedValueOnce({ ...fakeDevice, report_count_today: 10 });

    const res = await request(app).post(BASE).send(validBody);

    expect(res.status).toBe(429);
    expect(res.body.error).toContain('limit');
  });
});

// ────────────────────────────────────────────────
// GET /api/v1/reports
// ────────────────────────────────────────────────
describe('GET /api/v1/reports', () => {
  it('returns nearby reports with metadata', async () => {
    mockReport.findNearby.mockResolvedValueOnce([fakeReport]);

    const res = await request(app).get(BASE).query({ lat: 40.71, lng: -74.0, radius: 5000 });

    expect(res.status).toBe(200);
    expect(res.body.data).toHaveLength(1);
    expect(res.body.meta).toEqual(
      expect.objectContaining({ lat: 40.71, lng: -74, radius: 5000, count: 1 }),
    );
    expect(mockReport.findNearby).toHaveBeenCalledWith(40.71, -74, 5000, { limit: 20, offset: 0 });
  });

  it('applies custom pagination', async () => {
    mockReport.findNearby.mockResolvedValueOnce([]);

    const res = await request(app).get(BASE).query({ lat: 40.71, lng: -74.0, limit: 5, offset: 10 });

    expect(res.status).toBe(200);
    expect(mockReport.findNearby).toHaveBeenCalledWith(40.71, -74, 5000, { limit: 5, offset: 10 });
  });

  it('returns 400 when lat/lng are missing', async () => {
    const res = await request(app).get(BASE);

    expect(res.status).toBe(400);
    expect(res.body.error).toBe('Validation failed');
  });

  it('returns 400 when radius is too large', async () => {
    const res = await request(app).get(BASE).query({ lat: 40.71, lng: -74.0, radius: 999999 });

    expect(res.status).toBe(400);
    expect(res.body.details).toEqual(
      expect.arrayContaining([expect.objectContaining({ field: 'radius' })]),
    );
  });
});

// ────────────────────────────────────────────────
// GET /api/v1/reports/:id
// ────────────────────────────────────────────────
describe('GET /api/v1/reports/:id', () => {
  it('returns a report with media', async () => {
    mockReport.findById.mockResolvedValueOnce(fakeReport);
    mockMedia.findByReportId.mockResolvedValueOnce([
      {
        id: 'm-1',
        report_id: 'r-123',
        type: 'image',
        url: 'https://cdn/img.jpg',
        thumbnail_url: null,
        media_key: null,
        status: 'active',
        failure_reason: null,
        duration_ms: null,
        width: 1920,
        height: 1080,
        created_at: new Date(),
      },
    ]);

    const res = await request(app).get(`${BASE}/r-123`);

    expect(res.status).toBe(200);
    expect(res.body.id).toBe('r-123');
    expect(res.body.media).toHaveLength(1);
    expect(res.body.media[0].type).toBe('image');
  });

  it('returns 404 when report does not exist', async () => {
    mockReport.findById.mockResolvedValueOnce(null);

    const res = await request(app).get(`${BASE}/nonexistent`);

    expect(res.status).toBe(404);
    expect(res.body.error).toContain('not found');
  });
});

// ────────────────────────────────────────────────
// POST /api/v1/reports/:id/upvote
// ────────────────────────────────────────────────
describe('POST /api/v1/reports/:id/upvote', () => {
  it('adds an upvote and returns upvoted: true', async () => {
    mockReport.findById.mockResolvedValueOnce(fakeReport);
    mockUpvote.toggle.mockResolvedValueOnce(true);

    const res = await request(app).post(`${BASE}/r-123/upvote`).send({ device_id: 'device-1' });

    expect(res.status).toBe(200);
    expect(res.body.upvoted).toBe(true);
    expect(mockUpvote.toggle).toHaveBeenCalledWith('r-123', 'device-1');
  });

  it('removes an upvote and returns upvoted: false', async () => {
    mockReport.findById.mockResolvedValueOnce(fakeReport);
    mockUpvote.toggle.mockResolvedValueOnce(false);

    const res = await request(app).post(`${BASE}/r-123/upvote`).send({ device_id: 'device-1' });

    expect(res.status).toBe(200);
    expect(res.body.upvoted).toBe(false);
  });

  it('returns 404 when report does not exist', async () => {
    mockReport.findById.mockResolvedValueOnce(null);

    const res = await request(app).post(`${BASE}/nonexistent/upvote`).send({ device_id: 'device-1' });

    expect(res.status).toBe(404);
  });

  it('returns 400 when device_id is missing', async () => {
    const res = await request(app).post(`${BASE}/r-123/upvote`).send({});

    expect(res.status).toBe(400);
    expect(res.body.error).toBe('Validation failed');
  });
});

describe('POST /api/v1/reports — extended validation', () => {
  it('returns 400 when type is missing', async () => {
    const res = await request(app).post(BASE).send({ device_id: 'device-1', lat: 40.7128, lng: -74.006 });
    expect(res.status).toBe(400);
    expect(res.body.details).toEqual(expect.arrayContaining([expect.objectContaining({ field: 'type' })]));
  });
  it('returns 400 when lat is missing', async () => {
    const res = await request(app).post(BASE).send({ device_id: 'device-1', type: 'theft', lng: -74.006 });
    expect(res.status).toBe(400);
    expect(res.body.details).toEqual(expect.arrayContaining([expect.objectContaining({ field: 'lat' })]));
  });
  it('returns 400 when lng is missing', async () => {
    const res = await request(app).post(BASE).send({ device_id: 'device-1', type: 'theft', lat: 40.7128 });
    expect(res.status).toBe(400);
    expect(res.body.details).toEqual(expect.arrayContaining([expect.objectContaining({ field: 'lng' })]));
  });
});

describe('GET /api/v1/reports — extended', () => {
  it('returns empty data when offset exceeds total', async () => {
    mockReport.findNearby.mockResolvedValueOnce([]);
    const res = await request(app).get(BASE).query({ lat: 40.71, lng: -74.0, radius: 5000, offset: 999 });
    expect(res.status).toBe(200);
    expect(res.body.data).toEqual([]);
    expect(res.body.meta.count).toBe(0);
  });
});

describe('POST /api/v1/reports/:id/upvote — extended', () => {
  it('returns 404 for non-existent report', async () => {
    mockReport.findById.mockResolvedValueOnce(null);
    const res = await request(app).post(`${BASE}/does-not-exist/upvote`).send({ device_id: 'device-1' });
    expect(res.status).toBe(404);
  });
});
