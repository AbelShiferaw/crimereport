import { Router } from 'express';
import { checkHealth as checkDb } from '../lib/db';
import { checkHealth as checkRedis } from '../lib/redis';
import { isRedisAdapterHealthy } from '../lib/socket';

const router = Router();

router.get('/health', (_req, res) => {
  res.json({
    status: 'ok',
    timestamp: new Date().toISOString(),
    uptime: process.uptime(),
  });
});

router.get('/health/ready', async (_req, res) => {
  const [db, redis] = await Promise.all([checkDb(), checkRedis()]);
  const socketAdapter = isRedisAdapterHealthy();

  const allHealthy = db && redis && socketAdapter;

  res.status(allHealthy ? 200 : 503).json({
    status: allHealthy ? 'ok' : 'degraded',
    timestamp: new Date().toISOString(),
    uptime: process.uptime(),
    checks: {
      db: db ? 'connected' : 'disconnected',
      redis: redis ? 'connected' : 'disconnected',
      socketAdapter: socketAdapter ? 'connected' : 'disconnected',
    },
  });
});

export default router;
