import rateLimit from 'express-rate-limit';
import { config } from '../config';
import { recordRateLimitHit } from '../lib/metrics';
import { logger } from '../lib/logger';

export const globalLimiter = rateLimit({
  windowMs: 60 * 1000,
  limit: 100,
  standardHeaders: 'draft-7',
  legacyHeaders: false,
  skip: () => config.isDev,
  message: { error: 'Too many requests, please try again later' },
  handler: (_req, res, _next, options) => {
    recordRateLimitHit('global').catch((err) =>
      logger.warn({ err }, 'failed to record RateLimitHits metric'),
    );
    res.status(options.statusCode).json(options.message);
  },
});

export const writeLimiter = rateLimit({
  windowMs: 60 * 1000,
  limit: 20,
  standardHeaders: 'draft-7',
  legacyHeaders: false,
  skip: () => config.isDev,
  message: { error: 'Too many write requests, please try again later' },
  handler: (_req, res, _next, options) => {
    recordRateLimitHit('write').catch((err) =>
      logger.warn({ err }, 'failed to record RateLimitHits metric'),
    );
    res.status(options.statusCode).json(options.message);
  },
});
