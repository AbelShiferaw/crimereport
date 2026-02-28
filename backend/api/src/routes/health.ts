import { Router } from 'express';
import { checkHealth as checkDb } from '../lib/db';
import { checkHealth as checkRedis } from '../lib/redis';

const router = Router();

router.get('/health', async (_req, res) => {
  const [db, redis] = await Promise.all([checkDb(), checkRedis()]);

  const allHealthy = db && redis;

  res.status(allHealthy ? 200 : 503).json({
    status: allHealthy ? 'ok' : 'degraded',
    timestamp: new Date().toISOString(),
    uptime: process.uptime(),
    checks: { db: db ? 'connected' : 'disconnected', redis: redis ? 'connected' : 'disconnected' },
  });
});

export default router;
