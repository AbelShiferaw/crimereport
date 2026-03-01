import * as dbModule from '../../lib/db';
import * as redisModule from '../../lib/redis';
import * as socketModule from '../../lib/socket';

jest.mock('../../lib/db');
jest.mock('../../lib/redis');
jest.mock('../../lib/socket');

const mockCheckDb = dbModule.checkHealth as jest.MockedFunction<typeof dbModule.checkHealth>;
const mockCheckRedis = redisModule.checkHealth as jest.MockedFunction<typeof redisModule.checkHealth>;
const mockSocketHealth = socketModule.isRedisAdapterHealthy as jest.MockedFunction<typeof socketModule.isRedisAdapterHealthy>;

import request from 'supertest';
import app from '../../app';

beforeEach(() => {
  mockSocketHealth.mockReturnValue(true);
});

describe('GET /health (liveness)', () => {
  it('always returns 200 with status ok', async () => {
    const res = await request(app).get('/health');

    expect(res.status).toBe(200);
    expect(res.body.status).toBe('ok');
    expect(res.body.uptime).toBeDefined();
  });
});

describe('GET /health/ready (readiness)', () => {
  it('returns 200 when DB, Redis, and socket adapter are healthy', async () => {
    mockCheckDb.mockResolvedValueOnce(true);
    mockCheckRedis.mockResolvedValueOnce(true);

    const res = await request(app).get('/health/ready');

    expect(res.status).toBe(200);
    expect(res.body.status).toBe('ok');
    expect(res.body.checks.db).toBe('connected');
    expect(res.body.checks.redis).toBe('connected');
    expect(res.body.checks.socketAdapter).toBe('connected');
  });

  it('returns 503 when DB is down', async () => {
    mockCheckDb.mockResolvedValueOnce(false);
    mockCheckRedis.mockResolvedValueOnce(true);

    const res = await request(app).get('/health/ready');

    expect(res.status).toBe(503);
    expect(res.body.status).toBe('degraded');
    expect(res.body.checks.db).toBe('disconnected');
  });

  it('returns 503 when Redis is down', async () => {
    mockCheckDb.mockResolvedValueOnce(true);
    mockCheckRedis.mockResolvedValueOnce(false);

    const res = await request(app).get('/health/ready');

    expect(res.status).toBe(503);
    expect(res.body.status).toBe('degraded');
    expect(res.body.checks.redis).toBe('disconnected');
  });

  it('returns 503 when socket adapter is down', async () => {
    mockCheckDb.mockResolvedValueOnce(true);
    mockCheckRedis.mockResolvedValueOnce(true);
    mockSocketHealth.mockReturnValueOnce(false);

    const res = await request(app).get('/health/ready');

    expect(res.status).toBe(503);
    expect(res.body.status).toBe('degraded');
    expect(res.body.checks.socketAdapter).toBe('disconnected');
  });

  it('returns 503 when all are down', async () => {
    mockCheckDb.mockResolvedValueOnce(false);
    mockCheckRedis.mockResolvedValueOnce(false);
    mockSocketHealth.mockReturnValueOnce(false);

    const res = await request(app).get('/health/ready');

    expect(res.status).toBe(503);
    expect(res.body.status).toBe('degraded');
  });
});
