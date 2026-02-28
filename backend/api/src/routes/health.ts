import { Router } from 'express';
import { checkHealth as checkDb } from '../lib/db';
import { checkHealth as checkRedis } from '../lib/redis';

const router = Router();

// Liveness: is the process running? Used by container health check and ALB.
router.get('/health', (_req, res) => {
  res.json({
    status: 'ok',
    timestamp: new Date().toISOString(),
    uptime: process.uptime(),
  });
});

// Readiness: can the service handle requests? Checks DB + Redis connectivity.
router.get('/health/ready', async (_req, res) => {
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
