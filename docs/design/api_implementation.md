# CrImEreport API -- Implementation Guide

A comprehensive walkthrough of the backend API: how it's built, how every layer works, and how all the pieces connect.

---

## Table of Contents

1. [Overview](#overview)
2. [Tech Stack](#tech-stack)
3. [Project Structure](#project-structure)
4. [How Express Works](#how-express-works)
5. [Server Bootstrap](#server-bootstrap)
6. [Middleware Pipeline](#middleware-pipeline)
7. [Route Architecture](#route-architecture)
8. [Validation Layer (Zod)](#validation-layer-zod)
9. [Model Layer (Database Access)](#model-layer-database-access)
10. [Database Schema](#database-schema)
11. [PostgreSQL Connection](#postgresql-connection)
12. [Redis Connection](#redis-connection)
13. [S3 & CDN Integration](#s3--cdn-integration)
14. [Error Handling](#error-handling)
15. [Report Endpoints](#report-endpoints)
16. [Comment Endpoints](#comment-endpoints)
17. [Media Upload Flow](#media-upload-flow)
18. [Device Activity & Rate Limiting](#device-activity--rate-limiting)
19. [Transactional Operations](#transactional-operations)
20. [Health Endpoints](#health-endpoints)
21. [Logging](#logging)
22. [Configuration](#configuration)
23. [Graceful Shutdown](#graceful-shutdown)
24. [Docker & Deployment](#docker--deployment)
25. [Testing](#testing)
26. [Request Lifecycle (End-to-End)](#request-lifecycle-end-to-end)
27. [Real-Time Layer (WebSocket / Socket.io)](#real-time-layer-websocket--socketio)

---

## Overview

The CrImEreport API is a TypeScript REST server built on Express.js. It handles crime report creation, geospatial queries, anonymous commenting, media uploads via presigned S3 URLs, and device-based rate limiting. The server runs on AWS ECS Fargate behind an Application Load Balancer with WAF protection.

Key characteristics:
- **No authentication** -- fully anonymous, identified only by hashed device IDs
- **No ORM** -- raw SQL via the `pg` driver for full control over PostGIS queries
- **Flat architecture** -- route handlers call model functions directly (no controller/service layers)
- **Zod validation** -- type-safe request validation with automatic error formatting
- **Pino logging** -- structured JSON logs in production, pretty-printed in development

---

## Tech Stack

| Component | Library | Purpose |
|-----------|---------|---------|
| Runtime | Node.js 20 | JavaScript runtime |
| Language | TypeScript 5.3 | Type safety |
| Framework | Express 4 | HTTP routing and middleware |
| Validation | Zod 4 | Request schema validation |
| Database | pg 8 | PostgreSQL client with connection pooling |
| Migrations | node-pg-migrate 8 | SQL-based schema migrations |
| Cache | redis 4 | Redis client (ElastiCache) |
| WebSocket | socket.io 4 | Real-time communication (basic setup, Milestone 23 expands this) |
| S3 | @aws-sdk/client-s3, @aws-sdk/s3-request-presigner | Media upload presigned URLs |
| Logging | pino + pino-http | Structured logging |
| Security | helmet | HTTP security headers |
| Testing | jest + supertest + ts-jest | Unit and integration tests |

---

## Project Structure

```
backend/api/
├── Dockerfile                          # Multi-stage Node 20 Alpine build
├── package.json                        # Dependencies and npm scripts
├── tsconfig.json                       # TypeScript config (ES2022, strict)
├── jest.config.ts                      # Jest with ts-jest preset
├── migrations/                         # SQL migration files (node-pg-migrate)
│   ├── 1709000000000_initial-schema.sql
│   ├── 1709100000000_add-comment-flags.sql
│   └── 1709200000000_add-media-key.sql
├── scripts/
│   └── migrate.js                      # Pre-boot migration runner
└── src/
    ├── index.ts                        # HTTP + Socket.io server, shutdown
    ├── app.ts                          # Express app, middleware chain
    ├── config/
    │   └── index.ts                    # Typed env config with helpers
    ├── lib/
    │   ├── db.ts                       # PostgreSQL pool, query(), getClient()
    │   ├── redis.ts                    # Redis client with lazy connect
    │   ├── s3.ts                       # Presigned URLs, CDN URL builder
    │   ├── errors.ts                   # HttpError class
    │   └── logger.ts                   # Pino logger
    ├── middleware/
    │   ├── request-id.ts               # x-request-id propagation
    │   ├── request-logger.ts           # pino-http request/response logging
    │   ├── validate.ts                 # Zod schema validation middleware
    │   ├── error-handler.ts            # Centralized error responses
    │   └── not-found.ts                # 404 catch-all
    ├── models/
    │   ├── types.ts                    # Shared TypeScript interfaces
    │   ├── report.ts                   # Report queries (PostGIS)
    │   ├── comment.ts                  # Comment queries (transactional)
    │   ├── media.ts                    # Media record queries
    │   ├── report-upvote.ts            # Upvote toggle (transactional)
    │   ├── comment-flag.ts             # Comment flagging (transactional)
    │   └── device-activity.ts          # Device tracking and rate limits
    ├── routes/
    │   ├── index.ts                    # Mounts /reports and /comments
    │   ├── reports.ts                  # All report, comment, and media routes
    │   ├── comments.ts                 # Comment flag route
    │   └── health.ts                   # Liveness + readiness probes
    ├── validators/
    │   ├── report.ts                   # Zod schemas for reports
    │   ├── comment.ts                  # Zod schemas for comments
    │   └── media.ts                    # Zod schemas for media uploads
    └── __tests__/                      # Jest test files
        ├── routes/
        │   ├── reports.test.ts
        │   ├── comments.test.ts
        │   ├── media-upload.test.ts
        │   └── health.test.ts
        └── models/
            ├── report.test.ts
            ├── comment.test.ts
            ├── media.test.ts
            ├── report-upvote.test.ts
            ├── comment-flag.test.ts
            └── device-activity.test.ts
```

---

## How Express Works

Express is a minimal web framework for Node.js. At its core, it's a pipeline of **middleware functions** that process HTTP requests in order.

### The Middleware Concept

Every middleware function receives three arguments: `(req, res, next)`. It can:
1. **Read/modify** the request or response objects
2. **Send a response** (ending the pipeline)
3. **Call `next()`** to pass control to the next middleware

```
Request → [Middleware 1] → [Middleware 2] → [Route Handler] → Response
              │                  │                │
          request-id          helmet          business logic
```

### Routing

Express uses a `Router` to group related endpoints. Our API mounts routers like this:

```
app
├── healthRouter          → GET /health, GET /health/ready
└── apiRouter (/api/v1)
    ├── reportRouter      → /api/v1/reports/*
    └── commentRouter     → /api/v1/comments/*
```

Each route can have its own middleware (like validation) that runs before the handler:

```typescript
router.post('/', validate(createReportSchema), async (req, res) => {
  // validate() already parsed and validated req.body
  // If validation failed, a 400 was sent and this never runs
  const { device_id, type, description, lat, lng } = req.body;
  // ... business logic
});
```

### Async Error Handling

We import `express-async-errors` at the top of `app.ts`. This monkey-patches Express so that any thrown error (including from `async` handlers) automatically gets caught and forwarded to the error handler middleware. Without it, thrown errors in async handlers would crash the process.

---

## Server Bootstrap

The server starts in `src/index.ts`:

```typescript
// src/index.ts
import { createServer } from 'http';
import { Server as SocketServer } from 'socket.io';
import app from './app';

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
```

The HTTP server wraps the Express app, and Socket.io attaches to it. Both HTTP and WebSocket traffic share the same port. Socket.io is currently in basic mode (connect/disconnect logging). Milestone 23 adds the Redis adapter and geo-based rooms.

---

## Middleware Pipeline

Every request flows through this exact order (defined in `src/app.ts`):

```typescript
// src/app.ts
import 'express-async-errors';

const app = express();

// 1. Request ID — assigns or propagates x-request-id
app.use(requestId);

// 2. Security headers — Strict-Transport-Security, X-Content-Type-Options, etc.
app.use(helmet());

// 3. Compression — gzip responses
app.use(compression());

// 4. CORS — allows cross-origin requests
app.use(cors({ origin: config.corsOrigin }));

// 5. JSON parsing — parses request bodies up to 1MB
app.use(express.json({ limit: '1mb' }));

// 6. Request logging — pino-http logs method, url, status, duration
app.use(requestLogger);

// 7. Routes
app.use(healthRouter);              // GET /health, GET /health/ready
app.use('/api/v1', apiRouter);      // All API routes under /api/v1

// 8. 404 catch-all — any unmatched route
app.use(notFoundHandler);

// 9. Error handler — catches all thrown/rejected errors
app.use(errorHandler);
```

### Request ID Middleware

Every request gets a UUID in the `x-request-id` header. If a load balancer or client already set one, we reuse it. This ID appears in all log lines for that request, making distributed tracing possible.

```typescript
export function requestId(req: Request, res: Response, next: NextFunction): void {
  const id = (req.headers['x-request-id'] as string) || uuidv4();
  req.headers['x-request-id'] = id;
  res.setHeader('x-request-id', id);
  next();
}
```

### Request Logger

Uses `pino-http` which logs every request/response pair with method, URL, status code, and duration. Skips `/health` to avoid flooding logs.

```typescript
export const requestLogger = pinoHttp({
  logger,
  autoLogging: {
    ignore: (req) => req.url === '/health',
  },
});
```

### Validate Middleware

A factory function that takes a Zod schema and a target (`body`, `query`, or `params`). Returns middleware that validates and replaces the raw data with the parsed (coerced + defaulted) result.

```typescript
export function validate(schema: ZodSchema, property: RequestProperty = 'body') {
  return (req: Request, res: Response, next: NextFunction): void => {
    const result = schema.safeParse(req[property]);

    if (!result.success) {
      const errors = formatZodErrors(result.error);
      res.status(400).json({ error: 'Validation failed', details: errors });
      return;
    }

    req[property] = result.data;  // Replace with parsed data
    next();
  };
}
```

This means route handlers always receive validated, typed data. Query parameters are coerced from strings to numbers where needed.

### Error Handler

The final middleware catches any error thrown during request processing. It checks for a `statusCode` property (set by `HttpError`) and returns an appropriate JSON response. In production, 5xx errors are sanitized to hide internal details.

```typescript
export function errorHandler(err: AppError, _req: Request, res: Response, _next: NextFunction): void {
  const statusCode = err.statusCode ?? 500;
  logger.error({ err, statusCode }, err.message);

  res.status(statusCode).json({
    error: statusCode >= 500 ? 'Internal Server Error' : err.message,
    ...(process.env.NODE_ENV !== 'production' && { stack: err.stack }),
  });
}
```

---

## Route Architecture

All API routes are mounted under `/api/v1` via `routes/index.ts`:

```typescript
// routes/index.ts
const router = Router();

router.get('/', (_req, res) => {
  res.json({ name: 'CrimeReport API', version: '1.0.0' });
});

router.use('/reports', reportRouter);     // All report routes
router.use('/comments', commentRouter);   // Comment flagging only
```

### The Reports Router (`routes/reports.ts`)

This is the largest file -- it contains routes for reports, comments (nested under reports), and media uploads. The routes are grouped logically:

| Route | Method | Purpose |
|-------|--------|---------|
| `/reports` | POST | Create report |
| `/reports` | GET | Nearby search |
| `/reports/:id` | GET | Single report + media |
| `/reports/:id/upvote` | POST | Toggle upvote |
| `/reports/:id/comments` | GET | List comments |
| `/reports/:id/comments` | POST | Create comment |
| `/reports/:id/upload` | POST | Get presigned upload URL |
| `/reports/:id/upload/complete` | POST | Confirm upload done |
| `/reports/:id/media/status` | GET | Poll processing status |

### The Comments Router (`routes/comments.ts`)

Only contains comment flagging, which needs a top-level route because it operates on comment IDs (not report IDs):

| Route | Method | Purpose |
|-------|--------|---------|
| `/comments/:id/flag` | POST | Flag a comment |

---

## Validation Layer (Zod)

Each route group has a corresponding validator file containing Zod schemas.

### Report Validators (`validators/report.ts`)

```typescript
export const CRIME_TYPES = [
  'theft', 'assault', 'vandalism', 'robbery', 'burglary',
  'suspicious', 'shooting', 'carjacking', 'harassment', 'drug_activity', 'other',
] as const;

export const createReportSchema = z.object({
  device_id: z.string().min(1).max(64),
  type: z.enum(CRIME_TYPES),
  description: z.string().max(2000).optional(),
  lat: z.number().min(-90).max(90),
  lng: z.number().min(-180).max(180),
  address: z.string().max(255).optional(),
});

export const nearbyQuerySchema = z.object({
  lat: z.coerce.number().min(-90).max(90),
  lng: z.coerce.number().min(-180).max(180),
  radius: z.coerce.number().min(100).max(50_000).default(5_000),
  limit: z.coerce.number().int().min(1).max(100).default(20),
  offset: z.coerce.number().int().min(0).default(0),
});
```

Note `z.coerce.number()` in the query schema -- query parameters arrive as strings, so Zod coerces them to numbers. The `.default()` calls provide fallback values.

### Comment Validators (`validators/comment.ts`)

```typescript
export const createCommentSchema = z.object({
  device_id: z.string().min(1).max(64),
  content: z.string().trim().min(1).max(1000),
});
```

The `.trim().min(1)` chain ensures whitespace-only comments are rejected.

### Media Validators (`validators/media.ts`)

```typescript
const ALLOWED_IMAGE_TYPES = ['image/jpeg', 'image/png', 'image/webp'] as const;
const ALLOWED_VIDEO_TYPES = ['video/mp4', 'video/quicktime', 'video/webm'] as const;

export const uploadRequestSchema = z.object({
  device_id: z.string().min(1).max(64),
  file_type: z.enum(['image', 'video']),
  content_type: z.enum([...ALLOWED_IMAGE_TYPES, ...ALLOWED_VIDEO_TYPES]),
}).refine(
  (data) => {
    if (data.file_type === 'image') {
      return (ALLOWED_IMAGE_TYPES as readonly string[]).includes(data.content_type);
    }
    return (ALLOWED_VIDEO_TYPES as readonly string[]).includes(data.content_type);
  },
  { message: 'content_type does not match file_type', path: ['content_type'] },
);
```

The `.refine()` adds cross-field validation -- you can't submit `file_type: "image"` with `content_type: "video/mp4"`.

---

## Model Layer (Database Access)

Models are plain TypeScript modules that export functions for database operations. They use the `query()` helper from `lib/db.ts` which wraps `pg`'s pool query with debug logging.

### Pattern

```typescript
// models/report.ts
import { query } from '../lib/db';
import { ReportRow, CreateReportInput } from './types';

export async function findById(id: string): Promise<ReportRow | null> {
  const { rows } = await query<ReportRow>(
    `SELECT id, device_id, type, description,
            ST_Y(location::geometry) AS lat,
            ST_X(location::geometry) AS lng,
            address, status, upvotes, comment_count,
            created_at, updated_at
     FROM reports WHERE id = $1`,
    [id],
  );
  return rows[0] ?? null;
}
```

Key details:
- **Parameterized queries** (`$1`, `$2`, ...) -- prevents SQL injection
- **PostGIS functions** -- `ST_Y()` and `ST_X()` extract lat/lng from the `GEOGRAPHY` column
- **Typed returns** -- `query<ReportRow>` gives TypeScript type information on the result rows
- **Null coalescing** -- `rows[0] ?? null` for single-result queries

### Model Files

| Model | Responsibilities |
|-------|-----------------|
| `report.ts` | `findById`, `findNearby` (PostGIS), `create`, `updateStatus`, upvote/comment count helpers |
| `comment.ts` | `findById`, `findByReportId`, `create`, `createForReport` (transactional), `countTodayByDevice` |
| `media.ts` | `findByReportId`, `findByMediaKey`, `create`, `updateUrls`, `updateStatus` |
| `report-upvote.ts` | `toggle` (transactional: insert or delete + counter update) |
| `comment-flag.ts` | `flag` (transactional: insert + increment flag_count) |
| `device-activity.ts` | `getOrCreate` (upsert), `incrementReportCount`, `flag`, `resetDailyCounts` |

### Type Definitions (`models/types.ts`)

All interfaces are defined in a single file:

```typescript
export interface Report {
  id: string;
  device_id: string;
  type: string;
  description: string | null;
  location: Coordinates;
  address: string | null;
  status: string;
  upvotes: number;
  comment_count: number;
  created_at: Date;
  updated_at: Date;
}

export interface Media {
  id: string;
  report_id: string;
  type: 'video' | 'image';
  url: string;
  thumbnail_url: string | null;
  media_key: string | null;
  status: string;
  duration_ms: number | null;
  width: number | null;
  height: number | null;
  created_at: Date;
}

export interface Comment {
  id: string;
  report_id: string;
  device_id: string;
  content: string;
  upvotes: number;
  flag_count: number;
  created_at: Date;
}

export interface DeviceActivity {
  device_id: string;
  report_count_today: number;
  last_report_at: Date | null;
  flagged: boolean;
  created_at: Date;
}
```

---

## Database Schema

The database is Aurora Serverless v2 PostgreSQL with PostGIS. The schema is managed through three SQL migration files.

### Entity Relationship

```
reports (1) ──── (N) media
reports (1) ──── (N) comments
reports (1) ──── (N) report_upvotes
comments (1) ── (N) comment_flags
device_activity (standalone, keyed by device_id)
```

### Tables

#### reports
```sql
CREATE TABLE reports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    device_id VARCHAR(64) NOT NULL,
    type VARCHAR(50) NOT NULL,
    description TEXT,
    location GEOGRAPHY(POINT, 4326) NOT NULL,
    address VARCHAR(255),
    status VARCHAR(20) NOT NULL DEFAULT 'pending',
    upvotes INTEGER NOT NULL DEFAULT 0,
    comment_count INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

The `location` column uses PostGIS `GEOGRAPHY(POINT, 4326)` which stores coordinates in WGS 84 (standard GPS) and enables distance calculations in meters. A GIST index on this column makes spatial queries fast.

Status values: `pending` → `uploading` → `processing` → `active` | `failed` | `removed`

An `updated_at` trigger fires on every UPDATE to keep the timestamp current.

#### media
```sql
CREATE TABLE media (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    report_id UUID NOT NULL REFERENCES reports(id) ON DELETE CASCADE,
    type VARCHAR(10) NOT NULL CHECK (type IN ('video', 'image')),
    url VARCHAR(500) NOT NULL,
    thumbnail_url VARCHAR(500),
    media_key VARCHAR(500),
    status VARCHAR(20) NOT NULL DEFAULT 'pending',
    duration_ms INTEGER,
    width INTEGER,
    height INTEGER,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

`media_key` is the S3 object key (e.g., `images/report-id/file-id.jpg`). It's used to check both the uploads and media buckets during status polling.

#### comments
```sql
CREATE TABLE comments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    report_id UUID NOT NULL REFERENCES reports(id) ON DELETE CASCADE,
    device_id VARCHAR(64) NOT NULL,
    content TEXT NOT NULL,
    upvotes INTEGER NOT NULL DEFAULT 0,
    flag_count INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

#### report_upvotes
```sql
CREATE TABLE report_upvotes (
    report_id UUID NOT NULL REFERENCES reports(id) ON DELETE CASCADE,
    device_id VARCHAR(64) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (report_id, device_id)
);
```

Composite primary key ensures one upvote per device per report.

#### comment_flags
```sql
CREATE TABLE comment_flags (
    comment_id UUID NOT NULL REFERENCES comments(id) ON DELETE CASCADE,
    device_id VARCHAR(64) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (comment_id, device_id)
);
```

Same pattern as upvotes -- one flag per device per comment.

#### device_activity
```sql
CREATE TABLE device_activity (
    device_id VARCHAR(64) PRIMARY KEY,
    report_count_today INTEGER NOT NULL DEFAULT 0,
    last_report_at TIMESTAMPTZ,
    flagged BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

Tracks per-device rate limiting and abuse flags.

---

## PostgreSQL Connection

`lib/db.ts` manages the connection pool:

```typescript
const pool = new Pool(buildPoolConfig());

export async function query<T extends QueryResultRow>(
  text: string,
  params?: unknown[],
): Promise<QueryResult<T>> {
  const start = Date.now();
  const result = await pool.query<T>(text, params);
  logger.debug({ query: text, duration: Date.now() - start, rows: result.rowCount }, 'pg query');
  return result;
}

export async function getClient() {
  const client = await pool.connect();
  return client;
}
```

Two ways to run queries:
- **`query()`** -- uses the pool directly (auto-returns connection). Used for simple reads and writes.
- **`getClient()`** -- checks out a dedicated connection for transactions. The caller must `BEGIN`, `COMMIT`/`ROLLBACK`, and `client.release()`.

### Secrets Manager Support

`DATABASE_URL` can be either a standard PostgreSQL connection string or a JSON object from AWS Secrets Manager:

```typescript
if (raw.startsWith('{')) {
  const secret = JSON.parse(raw);
  return {
    host: secret.host,
    port: secret.port,
    user: secret.username,
    password: secret.password,
    database: secret.dbname || secret.dbClusterIdentifier || 'postgres',
    ssl: { rejectUnauthorized: false },
  };
}
```

---

## Redis Connection

`lib/redis.ts` uses lazy initialization -- the client connects on first use:

```typescript
let client: RedisClientType | null = null;

export async function getClient(): Promise<RedisClientType> {
  if (client && client.isOpen) return client;

  client = createClient({
    socket: {
      host: config.redis.host,
      port: config.redis.port,
      reconnectStrategy: (retries) => Math.min(retries * 100, 5_000),
    },
  });

  await client.connect();
  return client;
}
```

The reconnect strategy uses linear backoff capped at 5 seconds.

Currently Redis is only used for health checks. Milestone 23 adds the Socket.io Redis adapter for cross-task pub/sub.

---

## S3 & CDN Integration

`lib/s3.ts` provides four functions for the media upload flow:

### generateUploadUrl

Creates a presigned PUT URL for the client to upload directly to S3:

```typescript
export async function generateUploadUrl(key: string, contentType: string) {
  const command = new PutObjectCommand({
    Bucket: config.aws.s3UploadsBucket,
    Key: key,
    ContentType: contentType,
  });
  const url = await getSignedUrl(s3, command, { expiresIn: 900 }); // 15 minutes
  return { url, expiresIn: 900 };
}
```

### objectExists

Checks if an object exists in a bucket using `HeadObject`. Distinguishes between "not found" (returns false) and other S3 errors (re-throws):

```typescript
export async function objectExists(bucket: string, key: string): Promise<boolean> {
  try {
    await s3.send(new HeadObjectCommand({ Bucket: bucket, Key: key }));
    return true;
  } catch (err: any) {
    if (err.name === 'NotFound' || err.$metadata?.httpStatusCode === 404) {
      return false;
    }
    throw err; // Unexpected error (permissions, network, etc.)
  }
}
```

### buildMediaKey

Generates the S3 object key following a convention: `{type}/{reportId}/{fileId}.{ext}`

```typescript
export function buildMediaKey(fileType: 'image' | 'video', reportId: string, fileId: string, ext: string) {
  const prefix = fileType === 'image' ? 'images' : 'videos';
  return `${prefix}/${reportId}/${fileId}.${ext}`;
}
```

### buildCdnUrl

Constructs a CloudFront URL from an S3 key:

```typescript
export function buildCdnUrl(key: string): string {
  return `https://${config.aws.cdnDomain}/${key}`;
}
```

---

## Error Handling

`lib/errors.ts` defines an `HttpError` class with static factory methods:

```typescript
export class HttpError extends Error {
  public readonly statusCode: number;

  constructor(statusCode: number, message: string) {
    super(message);
    this.statusCode = statusCode;
    this.name = 'HttpError';
  }

  static badRequest(message = 'Bad Request')       { return new HttpError(400, message); }
  static forbidden(message = 'Forbidden')           { return new HttpError(403, message); }
  static notFound(message = 'Not Found')            { return new HttpError(404, message); }
  static conflict(message = 'Conflict')             { return new HttpError(409, message); }
  static tooManyRequests(message = 'Too Many Requests') { return new HttpError(429, message); }
}
```

Usage in routes:
```typescript
const report = await reportModel.findById(id);
if (!report) {
  throw HttpError.notFound('Report not found');
}
```

Because `express-async-errors` is imported, this thrown error is caught by the error handler middleware, which reads `statusCode` and sends the JSON response.

---

## Report Endpoints

### POST /api/v1/reports -- Create Report

```
Client → validate(createReportSchema) → check device flagged → check rate limit → create report → increment device count → 201
```

Edge cases:
- Flagged devices get 403
- More than 10 reports/day gets 429
- PostGIS `ST_MakePoint(lng, lat)` stores the location (note: PostGIS uses lng,lat order)

### GET /api/v1/reports -- Nearby Search

```
Client → validate(nearbyQuerySchema, 'query') → PostGIS ST_DWithin query → 200
```

The query uses `ST_DWithin(location, point, radius_meters)` with a GIST index for fast spatial filtering. Results include `distance_m` computed by `ST_Distance`. Removed reports are excluded.

### GET /api/v1/reports/:id -- Single Report

Returns the report joined with all its media records. No validation needed beyond the path parameter.

### POST /api/v1/reports/:id/upvote -- Toggle Upvote

Uses a transaction to atomically check for an existing upvote, insert or delete it, and update the counter:

```
BEGIN → SELECT report FOR UPDATE → check upvote exists?
  → YES: DELETE upvote, decrement counter, return { upvoted: false }
  → NO:  INSERT upvote, increment counter, return { upvoted: true }
COMMIT
```

The `FOR UPDATE` lock prevents race conditions when multiple devices upvote simultaneously.

---

## Comment Endpoints

### GET /api/v1/reports/:id/comments

Paginated list ordered by `created_at DESC`.

### POST /api/v1/reports/:id/comments

```
Client → validate → check report exists → check report not removed → check device not flagged → check daily limit → createForReport (transaction) → 201
```

Edge cases:
- Cannot comment on removed reports (403)
- Flagged devices blocked (403)
- Max 50 comments per device per day (429)
- Whitespace-only content rejected (Zod `.trim().min(1)`)

The `createForReport` function uses a transaction to atomically insert the comment and increment `report.comment_count`.

### POST /api/v1/comments/:id/flag

```
Client → validate → check comment exists → flag (transaction) → 200
```

The flag transaction inserts a row in `comment_flags` and increments `comment.flag_count`. If the device already flagged the comment, it returns `{ flagged: false }` without error.

---

## Media Upload Flow

The upload uses a two-phase approach where the client uploads directly to S3, not through our API:

```
Phase 1: Get presigned URL
  Client → POST /reports/:id/upload → API creates media record + presigned URL
  Client ← { upload_url, media_key, expires_in: 900 }

Phase 2: Direct upload to S3
  Client → PUT upload_url (with file bytes) → S3

Phase 3: Confirm completion
  Client → POST /reports/:id/upload/complete { media_key }
  API → HeadObject on uploads bucket to verify file exists
  API → Sets media.status = 'processing', report.status = 'processing'

Phase 4: S3 triggers Step Functions pipeline
  EventBridge → Step Functions → Rekognition → MediaConvert → media bucket

Phase 5: Client polls for status
  Client → GET /reports/:id/media/status
  API → Checks both S3 buckets:
    - File in media bucket? → Update URLs, set status = 'active'
    - File gone from uploads bucket? → Set status = 'failed'
    - File still in uploads bucket? → Still 'processing'
```

### Upload Endpoint Edge Cases

The `POST /:id/upload` route checks:
1. Report exists (404)
2. Requesting device owns the report (403)
3. Report not removed (403)
4. Report status allows uploads -- only `pending`, `uploading`, or `failed` (409)
5. Device not flagged (403)
6. Media count under limit of 5 per report (400)

### Status Polling Logic

The `GET /:id/media/status` endpoint doesn't just read from the database -- it actively checks S3:

```typescript
// For each media item that isn't already 'active':
const processed = await s3.objectExists(config.aws.s3MediaBucket, processedKey);

if (processed) {
  // File made it through the pipeline → update URLs and mark active
  const cdnUrl = s3.buildCdnUrl(processedKey);
  const thumbnailKey = processedKey.replace(/\.[^.]+$/, '_thumb.jpg');
  const hasThumb = await s3.objectExists(config.aws.s3MediaBucket, thumbnailKey);
  await mediaModel.updateUrls(processedKey, cdnUrl, hasThumb ? s3.buildCdnUrl(thumbnailKey) : null);
}

const stillInUploads = await s3.objectExists(config.aws.s3UploadsBucket, processedKey);
if (!stillInUploads && item.status === 'processing') {
  // File vanished from uploads AND didn't appear in media → pipeline failed
  await mediaModel.updateStatus(processedKey, 'failed');
}
```

This polling approach was chosen over webhooks for the MVP because it requires no additional infrastructure.

---

## Device Activity & Rate Limiting

Device tracking uses an upsert pattern:

```typescript
export async function getOrCreate(deviceId: string): Promise<DeviceActivity> {
  const { rows } = await query<DeviceActivity>(
    `INSERT INTO device_activity (device_id)
     VALUES ($1)
     ON CONFLICT (device_id) DO UPDATE SET device_id = EXCLUDED.device_id
     RETURNING device_id, report_count_today, last_report_at, flagged, created_at`,
    [deviceId],
  );
  return rows[0];
}
```

The `ON CONFLICT ... DO UPDATE` ensures a row always exists for the device. The route handlers then check:

```typescript
const device = await deviceActivity.getOrCreate(device_id);

if (device.flagged) {
  throw HttpError.forbidden('This device has been flagged for abuse');
}

if (device.report_count_today >= MAX_DAILY_REPORTS) {
  throw HttpError.tooManyRequests(`Daily report limit of ${MAX_DAILY_REPORTS} reached`);
}
```

| Rate Limit | Value | Scope |
|-----------|-------|-------|
| Reports | 10/day | Per device |
| Comments | 50/day | Per device |
| Media per report | 5 | Per report |

---

## Transactional Operations

Three operations use explicit transactions to maintain data consistency:

### Upvote Toggle (`report-upvote.ts`)
Locks the report row with `FOR UPDATE`, then either inserts or deletes the upvote and updates the counter. Prevents race conditions when multiple users upvote simultaneously.

### Comment Creation (`comment.ts`)
Atomically inserts the comment and increments `report.comment_count` to prevent count drift.

### Comment Flagging (`comment-flag.ts`)
Locks the comment row, checks for duplicate flags, inserts the flag, and increments `comment.flag_count`.

All three follow the same pattern:
```typescript
const client = await getClient();
try {
  await client.query('BEGIN');
  // ... operations using client.query() ...
  await client.query('COMMIT');
} catch (err) {
  await client.query('ROLLBACK');
  throw err;
} finally {
  client.release();
}
```

---

## Health Endpoints

### GET /health (Liveness)

Always returns 200 if the process is running. Used by the ECS container health check and ALB:

```json
{ "status": "ok", "timestamp": "...", "uptime": 12345.67 }
```

### GET /health/ready (Readiness)

Checks PostgreSQL and Redis connectivity. Returns 503 if either is down:

```typescript
const [db, redis] = await Promise.all([checkDb(), checkRedis()]);
res.status(allHealthy ? 200 : 503).json({
  status: allHealthy ? 'ok' : 'degraded',
  checks: { db: db ? 'connected' : 'disconnected', redis: redis ? 'connected' : 'disconnected' },
});
```

---

## Logging

Pino outputs structured JSON in production and pretty-printed colored output in development:

```typescript
export const logger = pino({
  level: config.isDev ? 'debug' : 'info',
  transport: config.isDev
    ? { target: 'pino-pretty', options: { colorize: true } }
    : undefined,
});
```

All database queries are logged at debug level with duration. All errors are logged with full stack traces. Request/response pairs are logged by pino-http.

---

## Configuration

`config/index.ts` provides a typed configuration object with `env()` and `envInt()` helpers:

```typescript
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

The `env()` helper throws if a required variable is missing (no fallback provided), making misconfiguration fail fast at startup rather than at runtime.

---

## Graceful Shutdown

When the process receives `SIGTERM` (ECS task stop) or `SIGINT` (Ctrl+C):

```typescript
function shutdown(signal: string) {
  logger.info({ signal }, 'shutdown signal received');

  httpServer.close(async () => {       // 1. Stop accepting new HTTP connections
    io.close(async () => {             // 2. Close WebSocket connections
      await pool.end();                // 3. Drain PostgreSQL connection pool
      await disconnectRedis();         // 4. Close Redis connection
      process.exit(0);
    });
  });

  setTimeout(() => {
    logger.error('graceful shutdown timed out, forcing exit');
    process.exit(1);
  }, 10_000);                          // 5. Force exit after 10s if stuck
}
```

This ensures in-flight requests complete before the process exits, and the 10-second timeout prevents zombie processes.

---

## Docker & Deployment

### Dockerfile

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

Key details:
- **Multi-stage build** -- the builder stage compiles TypeScript, the final image only includes production dependencies and compiled JS
- **Auto-migration** -- `scripts/migrate.js` runs pending migrations before starting the server
- **Non-root user** -- runs as the `node` user for security
- **curl installed** -- needed for ECS health checks

### Deployment

The Docker image is built by CDK's `DockerImageAsset`, pushed to ECR, and deployed to ECS Fargate. Environment variables are injected by the CDK Compute stack from Secrets Manager (database), CloudFormation outputs (Redis, S3, CDN), and stack parameters.

---

## Testing

Tests use Jest with ts-jest and Supertest. All database and external service calls are mocked at the module level.

### Route Tests

```typescript
// Mock all model dependencies at the top of the file
jest.mock('../../models/report');
jest.mock('../../models/media');
jest.mock('../../models/comment');

const mockReport = jest.mocked(await import('../../models/report'));

describe('POST /api/v1/reports', () => {
  it('creates a report', async () => {
    mockReport.create.mockResolvedValueOnce(fakeReport);
    mockDeviceActivity.getOrCreate.mockResolvedValueOnce(fakeDevice);

    const res = await request(app)
      .post('/api/v1/reports')
      .send({ device_id: 'dev1', type: 'theft', lat: 37.77, lng: -122.41 });

    expect(res.status).toBe(201);
    expect(res.body.type).toBe('theft');
  });
});
```

### Model Tests

```typescript
jest.mock('../../lib/db');
const mockQuery = jest.mocked((await import('../../lib/db')).query);

it('finds report by id', async () => {
  mockQuery.mockResolvedValueOnce({ rows: [fakeReport], rowCount: 1, ... });
  const result = await reportModel.findById('r-123');
  expect(result).toEqual(fakeReport);
  expect(mockQuery).toHaveBeenCalledWith(expect.stringContaining('WHERE id = $1'), ['r-123']);
});
```

### Test Coverage

| Category | Test Files | What's Covered |
|----------|-----------|----------------|
| Routes | 4 files | All endpoints, validation errors, edge cases |
| Models | 6 files | All query functions, transaction logic |

---

## Request Lifecycle (End-to-End)

Here's what happens when a client sends `POST /api/v1/reports`:

```
1. HTTP request hits ECS Fargate task (via ALB)
2. Express receives the request

3. requestId middleware
   → Assigns UUID to x-request-id header

4. helmet middleware
   → Adds security headers (X-Content-Type-Options, etc.)

5. compression middleware
   → Prepares gzip encoding for response

6. cors middleware
   → Adds Access-Control-Allow-Origin header

7. express.json middleware
   → Parses JSON body from raw bytes

8. requestLogger middleware
   → Logs: POST /api/v1/reports (start)

9. Route matching
   → /api/v1/reports matches reportRouter

10. validate(createReportSchema) middleware
    → Zod parses body, validates types/constraints
    → If invalid: returns 400 with field-level errors (pipeline stops)
    → If valid: replaces req.body with parsed data, calls next()

11. Route handler
    → deviceActivity.getOrCreate(device_id)  -- upserts device row
    → Checks device.flagged                  -- 403 if flagged
    → Checks device.report_count_today       -- 429 if over limit
    → reportModel.create(input)              -- INSERT with PostGIS
    → deviceActivity.incrementReportCount()  -- bumps daily counter
    → res.status(201).json(report)

12. requestLogger middleware
    → Logs: POST /api/v1/reports 201 45ms

13. Response sent to client through ALB
```

If any step throws an error:
```
→ express-async-errors catches the rejection
→ errorHandler middleware receives the error
→ Logs the error with Pino
→ Returns { error: "..." } with appropriate status code
```

---

## Real-Time Layer (WebSocket / Socket.io)

The API provides real-time updates to connected clients via Socket.io, running on the same HTTP server as the REST API.

### Architecture

```
src/lib/
├── socket.ts      # Socket.io server, Redis adapter, auth, room management
└── broadcast.ts   # Fire-and-forget broadcast helpers called from route handlers
```

Socket.io is initialised in `index.ts` with `await initSocket(httpServer)` before the server starts listening. This wraps the existing Node.js HTTP server with the Socket.io transport layer.

### How It Works

1. **Connection**: A client connects via WebSocket with `auth: { deviceId }`. The auth middleware validates the device ID (1-64 chars) and rejects invalid connections.

2. **Room Subscription**: Clients emit `subscribe:location` with `{ lat, lng }` to join a geo-grid room. The `locationRoom()` function maps coordinates to a 0.1-degree grid cell string like `location:40.7:-74.1`.

3. **Broadcasts**: When a mutation occurs (report activated, comment created, upvote toggled), the route handler calls a `broadcast.*` function. These are fire-and-forget — wrapped in try/catch so they never block the HTTP response.

4. **Geo-Grid Fan-Out**: For `report:new`, `overlappingRooms()` calculates the 3x3 grid of neighboring cells around the report's location and emits to all of them, ensuring users near grid boundaries receive the update.

5. **Redis Adapter**: In production, `@socket.io/redis-adapter` uses Redis Pub/Sub to synchronize broadcasts across all ECS Fargate tasks. Any server can emit to clients connected to any other server. Falls back to in-memory for local development.

### Key Implementation Details

**`lib/socket.ts`** exports:
- `initSocket(httpServer)` — Creates Socket.io server, connects Redis adapter, registers auth middleware and event handlers
- `getIO()` — Returns the Socket.io instance (throws if not initialised)
- `locationRoom(lat, lng)` — Maps coordinates to grid cell string
- `overlappingRooms(lat, lng)` — Returns 3x3 grid of room strings around a point
- `shutdownSocket()` — Gracefully closes all connections

**`lib/broadcast.ts`** exports:
- `broadcastNewReport(report)` — Emits `report:new` to all overlapping geo-rooms
- `broadcastNewComment(comment)` — Emits `comment:new` to report-specific room (excludes `device_id` from payload)
- `broadcastUpvote(reportId, upvoted)` — Emits `report:upvote` to report-specific room

### Broadcast Timing

| Event | Trigger | Timing |
|-------|---------|--------|
| `report:new` | `GET /reports/:id/media/status` | Only when all media transitions to `active` and report was not already `active` |
| `comment:new` | `POST /reports/:id/comments` | Immediately after comment creation |
| `report:upvote` | `POST /reports/:id/upvote` | Immediately after upvote toggle |

The `report:new` broadcast is deliberately delayed until media processing completes. This ensures reports without approved media never appear on other users' feeds. The double-broadcast race condition is prevented by checking `report.status !== 'active'` before broadcasting — once the status is set to `active`, subsequent poll requests skip the broadcast.

### Active-Only Feed

To maintain consistency between REST and WebSocket:
- `findNearby()` query filters by `status = 'active'` (not just `status != 'removed'`)
- Reports only become `active` after all media is processed
- Text-only reports (no media) never reach `active` status and are never broadcast
