# Milestone 18: API Server Foundation

## Status
Completed

## Goal
Build the TypeScript/Express API server foundation with middleware pipeline, health endpoints, structured logging, error handling, graceful shutdown, and Docker packaging.

## Dependencies
Requires **Milestone 17** complete (ECS Fargate running placeholder).

## What Was Built
A production-ready Express API server written in TypeScript. The server features a layered middleware stack (request IDs, security headers, compression, CORS, JSON parsing, structured logging), health/readiness endpoints with dependency checks, a centralized `HttpError` class, Zod-based request validation, Socket.IO wiring for future real-time features, graceful shutdown of HTTP + WebSocket + DB + Redis connections, and a multi-stage Docker build.

## Key Files

| File | Description |
|------|-------------|
| `backend/api/src/index.ts` | Entry point — HTTP server, Socket.IO bootstrap, graceful shutdown |
| `backend/api/src/app.ts` | Express app with full middleware chain |
| `backend/api/src/config/index.ts` | Typed environment config with `env()` / `envInt()` helpers |
| `backend/api/src/lib/logger.ts` | Pino logger (pretty in dev, JSON in prod) |
| `backend/api/src/lib/errors.ts` | `HttpError` class with static factory methods |
| `backend/api/src/middleware/request-id.ts` | Assigns/propagates `x-request-id` header |
| `backend/api/src/middleware/request-logger.ts` | `pino-http` request/response logging |
| `backend/api/src/middleware/error-handler.ts` | Global error handler — maps `statusCode`, hides stack in prod |
| `backend/api/src/middleware/not-found.ts` | Catch-all 404 for unmatched routes |
| `backend/api/src/middleware/validate.ts` | Zod schema validation for body/query/params |
| `backend/api/src/routes/health.ts` | `GET /health` (liveness) and `GET /health/ready` (readiness) |
| `backend/api/src/routes/index.ts` | Route aggregator — mounts reports and comments under `/api/v1` |
| `backend/api/package.json` | Dependencies and scripts |
| `backend/api/Dockerfile` | Multi-stage Node 20 Alpine build |
| `backend/api/tsconfig.json` | TypeScript compiler options (ES2022, strict) |

## Implementation Details

### 1. Express App Setup

The app mounts middleware in a strict order and registers routes:

```typescript
// backend/api/src/app.ts
import 'express-async-errors';
import express from 'express';
import compression from 'compression';
import cors from 'cors';
import helmet from 'helmet';
import { config } from './config';
import { requestId } from './middleware/request-id';
import { requestLogger } from './middleware/request-logger';
import { notFoundHandler } from './middleware/not-found';
import { errorHandler } from './middleware/error-handler';
import healthRouter from './routes/health';
import apiRouter from './routes';

const app = express();

app.use(requestId);
app.use(helmet());
app.use(compression());
app.use(cors({ origin: config.corsOrigin }));
app.use(express.json({ limit: '1mb' }));
app.use(requestLogger);

app.use(healthRouter);
app.use('/api/v1', apiRouter);

app.use(notFoundHandler);
app.use(errorHandler);

export default app;
```

`express-async-errors` patches Express so thrown errors inside `async` handlers are caught automatically — no manual `try/catch` or `next(err)` required.

### 2. Entry Point & Graceful Shutdown

The server wires up HTTP, Socket.IO, and signal handlers:

```typescript
// backend/api/src/index.ts
import { createServer } from 'http';
import { Server as SocketServer } from 'socket.io';
import app from './app';
import { config } from './config';
import { pool } from './lib/db';
import { disconnect as disconnectRedis } from './lib/redis';
import { logger } from './lib/logger';

const httpServer = createServer(app);

const io = new SocketServer(httpServer, {
  cors: { origin: config.corsOrigin, methods: ['GET', 'POST'] },
});

io.on('connection', (socket) => {
  logger.info({ socketId: socket.id }, 'client connected');
  socket.on('disconnect', () => {
    logger.info({ socketId: socket.id }, 'client disconnected');
  });
});

httpServer.listen(config.port, () => {
  logger.info({ port: config.port, env: config.nodeEnv }, 'CrimeReport API started');
});

function shutdown(signal: string) {
  logger.info({ signal }, 'shutdown signal received');
  httpServer.close(async () => {
    logger.info('http server closed');
    io.close(async () => {
      logger.info('socket.io closed');
      await pool.end().catch((err) => logger.error({ err }, 'error closing pg pool'));
      await disconnectRedis().catch((err) => logger.error({ err }, 'error closing redis'));
      process.exit(0);
    });
  });
  setTimeout(() => {
    logger.error('graceful shutdown timed out, forcing exit');
    process.exit(1);
  }, 10_000);
}

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));
```

Shutdown is ordered: HTTP → Socket.IO → PostgreSQL pool → Redis, with a 10-second hard timeout.

### 3. Configuration

Typed config object with `env()` and `envInt()` helpers that throw on missing required vars:

```typescript
// backend/api/src/config/index.ts
import dotenv from 'dotenv';
dotenv.config();

function env(key: string, fallback?: string): string {
  const value = process.env[key] ?? fallback;
  if (value === undefined) {
    throw new Error(`Missing required environment variable: ${key}`);
  }
  return value;
}

function envInt(key: string, fallback?: number): number {
  const raw = process.env[key];
  if (raw !== undefined) return parseInt(raw, 10);
  if (fallback !== undefined) return fallback;
  throw new Error(`Missing required environment variable: ${key}`);
}

export const config = {
  nodeEnv: env('NODE_ENV', 'development'),
  port: envInt('PORT', 3000),
  corsOrigin: env('CORS_ORIGIN', '*'),
  database: {
    url: env('DATABASE_URL', ''),
    poolMax: envInt('DB_POOL_MAX', 20),
    idleTimeoutMs: envInt('DB_IDLE_TIMEOUT_MS', 30_000),
    connectionTimeoutMs: envInt('DB_CONNECTION_TIMEOUT_MS', 5_000),
  },
  redis: {
    host: env('REDIS_HOST', 'localhost'),
    port: envInt('REDIS_PORT', 6379),
  },
  aws: {
    region: env('AWS_REGION', 'us-east-1'),
    s3UploadsBucket: env('S3_UPLOADS_BUCKET', ''),
    s3MediaBucket: env('S3_MEDIA_BUCKET', ''),
    cdnDomain: env('CDN_DOMAIN', ''),
  },
  get isDev() { return this.nodeEnv === 'development'; },
  get isProd() { return this.nodeEnv === 'production'; },
} as const;
```

### 4. Logger

Uses Pino with `pino-pretty` in development:

```typescript
// backend/api/src/lib/logger.ts
import pino from 'pino';
import { config } from '../config';

export const logger = pino({
  level: config.isDev ? 'debug' : 'info',
  transport: config.isDev
    ? { target: 'pino-pretty', options: { colorize: true } }
    : undefined,
});
```

### 5. Error Handling

A single `HttpError` class with static factory methods replaces the original multi-class pattern:

```typescript
// backend/api/src/lib/errors.ts
export class HttpError extends Error {
  public readonly statusCode: number;

  constructor(statusCode: number, message: string) {
    super(message);
    this.statusCode = statusCode;
    this.name = 'HttpError';
  }

  static badRequest(message = 'Bad Request') { return new HttpError(400, message); }
  static notFound(message = 'Not Found') { return new HttpError(404, message); }
  static forbidden(message = 'Forbidden') { return new HttpError(403, message); }
  static conflict(message = 'Conflict') { return new HttpError(409, message); }
  static tooManyRequests(message = 'Too Many Requests') { return new HttpError(429, message); }
}
```

The global error handler reads `statusCode` and hides internals in production:

```typescript
// backend/api/src/middleware/error-handler.ts
import { Request, Response, NextFunction } from 'express';
import { logger } from '../lib/logger';

export interface AppError extends Error { statusCode?: number; }

export function errorHandler(err: AppError, _req: Request, res: Response, _next: NextFunction): void {
  const statusCode = err.statusCode ?? 500;
  logger.error({ err, statusCode }, err.message);
  res.status(statusCode).json({
    error: statusCode >= 500 ? 'Internal Server Error' : err.message,
    ...(process.env.NODE_ENV !== 'production' && { stack: err.stack }),
  });
}
```

### 6. Middleware

**Request ID** — assigns or propagates `x-request-id`:

```typescript
// backend/api/src/middleware/request-id.ts
import { v4 as uuidv4 } from 'uuid';

export function requestId(req: Request, res: Response, next: NextFunction): void {
  const id = (req.headers['x-request-id'] as string) || uuidv4();
  req.headers['x-request-id'] = id;
  res.setHeader('x-request-id', id);
  next();
}
```

**Request Logger** — `pino-http` integration that skips `/health`:

```typescript
// backend/api/src/middleware/request-logger.ts
import pinoHttp from 'pino-http';
import { logger } from '../lib/logger';

export const requestLogger = pinoHttp({
  logger,
  autoLogging: { ignore: (req) => req.url === '/health' },
});
```

**Validation** — generic Zod middleware for body/query/params:

```typescript
// backend/api/src/middleware/validate.ts
import { ZodSchema, ZodError } from 'zod';

export function validate(schema: ZodSchema, property: RequestProperty = 'body') {
  return (req: Request, res: Response, next: NextFunction): void => {
    const result = schema.safeParse(req[property]);
    if (!result.success) {
      const errors = formatZodErrors(result.error);
      res.status(400).json({ error: 'Validation failed', details: errors });
      return;
    }
    req[property] = result.data;
    next();
  };
}
```

**Not Found** — catch-all for unmatched routes:

```typescript
// backend/api/src/middleware/not-found.ts
export function notFoundHandler(req: Request, res: Response): void {
  res.status(404).json({ error: 'Not Found', message: `Cannot ${req.method} ${req.path}` });
}
```

### 7. Health Endpoints

```typescript
// backend/api/src/routes/health.ts
import { Router } from 'express';
import { checkHealth as checkDb } from '../lib/db';
import { checkHealth as checkRedis } from '../lib/redis';

const router = Router();

router.get('/health', (_req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString(), uptime: process.uptime() });
});

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
```

### 8. Route Aggregator

```typescript
// backend/api/src/routes/index.ts
import { Router } from 'express';
import reportRouter from './reports';
import commentRouter from './comments';

const router = Router();

router.get('/', (_req, res) => {
  res.json({ name: 'CrimeReport API', version: '1.0.0' });
});

router.use('/reports', reportRouter);
router.use('/comments', commentRouter);

export default router;
```

### 9. Dockerfile

Multi-stage build on Node 20 Alpine. Runs migrations then starts the server:

```dockerfile
FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY tsconfig.json ./
COPY src ./src
RUN npm run build

FROM node:20-alpine
WORKDIR /app
RUN apk add --no-cache curl
COPY package*.json ./
RUN npm ci --omit=dev
COPY --from=builder /app/dist ./dist
COPY migrations ./migrations
COPY scripts ./scripts
EXPOSE 3000
USER node
CMD ["sh", "-c", "node scripts/migrate.js && node dist/index.js"]
```

### 10. TypeScript Configuration

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "commonjs",
    "lib": ["ES2022"],
    "outDir": "./dist",
    "rootDir": "./src",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "resolveJsonModule": true,
    "declaration": true,
    "declarationMap": true,
    "sourceMap": true
  },
  "include": ["src/**/*"],
  "exclude": ["node_modules", "dist"]
}
```

## Testing

A health endpoint test exists at `backend/api/src/__tests__/routes/health.test.ts`.

## Notes

**Deviations from original plan:**
- **TypeScript** instead of JavaScript throughout. All files use ES module `import`/`export` syntax compiled to CommonJS via `tsc`.
- **Pino** replaced Winston for structured logging (better performance, native JSON).
- **`pino-http`** replaced a custom `requestLogger` middleware.
- **Single `HttpError` class** with static factory methods (`notFound()`, `badRequest()`, etc.) replaced the multi-class error hierarchy (`AppError`, `NotFoundError`, `ValidationError`, etc.).
- **Zod** replaced Joi for request validation with tighter TypeScript integration.
- **`express-async-errors`** patches Express to catch async errors automatically — no wrapper needed.
- **Socket.IO** is wired up in `index.ts` from the start (planned for later milestone in the original design).
- **Request ID middleware** was added (not in original plan) for distributed tracing.
- **No separate `rateLimit` middleware** — rate limiting is handled at the route level via device activity tracking.
- **File structure** uses `lib/` instead of `utils/` and `config/` for DB/Redis moved to `lib/db.ts` and `lib/redis.ts`.
- **`not-found` middleware** was added as a dedicated catch-all handler.
