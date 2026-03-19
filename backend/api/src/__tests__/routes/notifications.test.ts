import * as pushModel from '../../models/push-subscription';
import * as snsLib from '../../lib/sns';
import * as dbHealth from '../../lib/db';
import * as redisHealth from '../../lib/redis';

jest.mock('../../models/push-subscription');
jest.mock('../../lib/sns');
jest.mock('../../lib/db');
jest.mock('../../lib/redis');
jest.mock('../../lib/socket');

const mockPush = pushModel as jest.Mocked<typeof pushModel>;
const mockSns = snsLib as jest.Mocked<typeof snsLib>;
const mockDbHealth = dbHealth as jest.Mocked<typeof dbHealth>;
const mockRedisHealth = redisHealth as jest.Mocked<typeof redisHealth>;

import request from 'supertest';
import app from '../../app';

const BASE = '/api/v1/notifications';

const fakeSubscription = {
  device_id: 'dev-1',
  fcm_token: 'tok-abc',
  platform: 'android' as const,
  endpoint_arn: 'arn:endpoint/1',
  lat: 40.71,
  lng: -74.0,
  radius: 10000,
  types: null,
  enabled: true,
  created_at: new Date('2025-01-01'),
  updated_at: new Date('2025-01-01'),
};

beforeEach(() => {
  jest.clearAllMocks();
  mockDbHealth.checkHealth.mockResolvedValue(true);
  mockRedisHealth.checkHealth.mockResolvedValue(true);
});

describe('POST /notifications/register', () => {
  it('registers a device and returns 201', async () => {
    mockSns.createEndpoint.mockResolvedValueOnce('arn:endpoint/1');
    mockPush.upsert.mockResolvedValueOnce(fakeSubscription);

    const res = await request(app).post(`${BASE}/register`).send({
      device_id: 'dev-1',
      fcm_token: 'tok-abc',
      platform: 'android',
      lat: 40.71,
      lng: -74.0,
    });

    expect(res.status).toBe(201);
    expect(res.body.device_id).toBe('dev-1');
    expect(mockSns.createEndpoint).toHaveBeenCalledWith('android', 'tok-abc', 'dev-1');
    expect(mockPush.upsert).toHaveBeenCalled();
  });

  it('returns 400 for missing fields', async () => {
    const res = await request(app).post(`${BASE}/register`).send({ device_id: 'dev-1' });
    expect(res.status).toBe(400);
  });

  it('returns 400 for invalid lat/lng', async () => {
    const res = await request(app).post(`${BASE}/register`).send({
      device_id: 'dev-1',
      fcm_token: 'tok',
      platform: 'android',
      lat: 999,
      lng: -74.0,
    });
    expect(res.status).toBe(400);
  });
});

describe('DELETE /notifications/unregister', () => {
  it('unregisters a device', async () => {
    mockPush.remove.mockResolvedValueOnce('arn:endpoint/1');
    mockSns.deleteEndpoint.mockResolvedValueOnce(undefined);

    const res = await request(app).delete(`${BASE}/unregister`).send({ device_id: 'dev-1' });
    expect(res.status).toBe(200);
    expect(mockPush.remove).toHaveBeenCalledWith('dev-1');
    expect(mockSns.deleteEndpoint).toHaveBeenCalledWith('arn:endpoint/1');
  });

  it('succeeds even when no subscription existed', async () => {
    mockPush.remove.mockResolvedValueOnce(null);

    const res = await request(app).delete(`${BASE}/unregister`).send({ device_id: 'dev-1' });
    expect(res.status).toBe(200);
    expect(mockSns.deleteEndpoint).not.toHaveBeenCalled();
  });
});

describe('PUT /notifications/preferences', () => {
  it('updates preferences', async () => {
    mockPush.updatePreferences.mockResolvedValueOnce({
      ...fakeSubscription,
      enabled: false,
      radius: 20000,
    });

    const res = await request(app).put(`${BASE}/preferences`).send({
      device_id: 'dev-1',
      enabled: false,
      radius: 20000,
    });

    expect(res.status).toBe(200);
    expect(res.body.enabled).toBe(false);
    expect(res.body.radius).toBe(20000);
  });

  it('returns 404 when device not found', async () => {
    mockPush.updatePreferences.mockResolvedValueOnce(null);

    const res = await request(app).put(`${BASE}/preferences`).send({
      device_id: 'nonexistent',
      enabled: true,
    });

    expect(res.status).toBe(404);
  });

  it('returns 400 for invalid radius', async () => {
    const res = await request(app).put(`${BASE}/preferences`).send({
      device_id: 'dev-1',
      radius: 100,
    });
    expect(res.status).toBe(400);
  });
});
