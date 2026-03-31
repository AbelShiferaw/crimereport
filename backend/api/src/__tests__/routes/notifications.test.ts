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

describe('PUT /notifications/preferences — extended', () => {
  it('returns 404 for non-existent device', async () => {
    mockPush.updatePreferences.mockResolvedValueOnce(null);
    const res = await request(app).put(`${BASE}/preferences`).send({ device_id: 'non-existent-device', enabled: true });
    expect(res.status).toBe(404);
  });
});

describe('DELETE /notifications/unregister — extended', () => {
  it('succeeds gracefully for non-existent device', async () => {
    mockPush.remove.mockResolvedValueOnce(null);
    const res = await request(app).delete(`${BASE}/unregister`).send({ device_id: 'non-existent-device' });
    expect(res.status).toBe(200);
    expect(mockSns.deleteEndpoint).not.toHaveBeenCalled();
  });
});

describe('POST /notifications/register — extended', () => {
  it('registers an iOS device', async () => {
    mockSns.createEndpoint.mockResolvedValueOnce('arn:ios-endpoint');
    mockPush.upsert.mockResolvedValueOnce({
      ...fakeSubscription,
      platform: 'ios' as const,
      endpoint_arn: 'arn:ios-endpoint',
    });

    const res = await request(app).post(`${BASE}/register`).send({
      device_id: 'ios-dev-1',
      fcm_token: 'ios-token-abc',
      platform: 'ios',
      lat: 37.78,
      lng: -122.41,
    });

    expect(res.status).toBe(201);
    expect(mockSns.createEndpoint).toHaveBeenCalledWith('ios', 'ios-token-abc', 'ios-dev-1');
  });

  it('returns 400 for invalid lng', async () => {
    const res = await request(app).post(`${BASE}/register`).send({
      device_id: 'dev-1',
      fcm_token: 'tok',
      platform: 'android',
      lat: 40.71,
      lng: 999,
    });
    expect(res.status).toBe(400);
  });

  it('returns 400 for invalid platform', async () => {
    const res = await request(app).post(`${BASE}/register`).send({
      device_id: 'dev-1',
      fcm_token: 'tok',
      platform: 'windows',
      lat: 40.71,
      lng: -74.0,
    });
    expect(res.status).toBe(400);
  });

  it('returns 400 for empty device_id', async () => {
    const res = await request(app).post(`${BASE}/register`).send({
      device_id: '',
      fcm_token: 'tok',
      platform: 'android',
      lat: 40.71,
      lng: -74.0,
    });
    expect(res.status).toBe(400);
  });

  it('returns 400 for empty fcm_token', async () => {
    const res = await request(app).post(`${BASE}/register`).send({
      device_id: 'dev-1',
      fcm_token: '',
      platform: 'android',
      lat: 40.71,
      lng: -74.0,
    });
    expect(res.status).toBe(400);
  });
});

describe('PUT /notifications/preferences — types array', () => {
  it('updates preferences with types array', async () => {
    mockPush.updatePreferences.mockResolvedValueOnce({
      ...fakeSubscription,
      types: ['theft', 'assault'],
    });

    const res = await request(app).put(`${BASE}/preferences`).send({
      device_id: 'dev-1',
      types: ['theft', 'assault'],
    });

    expect(res.status).toBe(200);
    expect(res.body.types).toEqual(['theft', 'assault']);
  });

  it('updates preferences with enabled only', async () => {
    mockPush.updatePreferences.mockResolvedValueOnce({
      ...fakeSubscription,
      enabled: false,
    });

    const res = await request(app).put(`${BASE}/preferences`).send({
      device_id: 'dev-1',
      enabled: false,
    });

    expect(res.status).toBe(200);
    expect(res.body.enabled).toBe(false);
  });

  it('updates all optional fields together', async () => {
    mockPush.updatePreferences.mockResolvedValueOnce({
      ...fakeSubscription,
      enabled: true,
      radius: 25000,
      types: ['robbery', 'vandalism'],
    });

    const res = await request(app).put(`${BASE}/preferences`).send({
      device_id: 'dev-1',
      enabled: true,
      radius: 25000,
      types: ['robbery', 'vandalism'],
    });

    expect(res.status).toBe(200);
    expect(res.body.radius).toBe(25000);
    expect(res.body.types).toEqual(['robbery', 'vandalism']);
  });
});

describe('notification validation edge cases', () => {
  it('register returns 400 for invalid types in preferences', async () => {
    const result = (await import('../../validators/push-subscription')).updatePreferencesSchema.safeParse({
      device_id: 'dev-1',
      types: ['invalid_crime'],
    });
    expect(result.success).toBe(false);
  });

  it('register returns 400 for radius below minimum via schema', async () => {
    const result = (await import('../../validators/push-subscription')).updatePreferencesSchema.safeParse({
      device_id: 'dev-1',
      radius: 999,
    });
    expect(result.success).toBe(false);
  });

  it('register returns 400 for radius above maximum via schema', async () => {
    const result = (await import('../../validators/push-subscription')).updatePreferencesSchema.safeParse({
      device_id: 'dev-1',
      radius: 50001,
    });
    expect(result.success).toBe(false);
  });

  it('unregister rejects missing device_id via schema', async () => {
    const result = (await import('../../validators/push-subscription')).unregisterDeviceSchema.safeParse({});
    expect(result.success).toBe(false);
  });

  it('unregister rejects empty device_id via schema', async () => {
    const result = (await import('../../validators/push-subscription')).unregisterDeviceSchema.safeParse({ device_id: '' });
    expect(result.success).toBe(false);
  });
});
