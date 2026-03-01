# CrImEreport API

TypeScript + Express REST API for the CrImEreport anonymous crime reporting platform.

## Quick Start

```bash
# Install dependencies
npm install

# Start dev server (auto-restarts on file changes)
npm run dev

# Build for production
npm run build

# Run production server
npm start
```

The server starts on `http://localhost:3000` by default.

## Architecture

```
src/
├── index.ts               # HTTP server, Socket.io init, graceful shutdown
├── app.ts                 # Express app with middleware chain
├── config/index.ts        # Typed env config
├── lib/
│   ├── db.ts              # PostgreSQL pool + query helpers
│   ├── redis.ts           # Redis client
│   ├── s3.ts              # Presigned URLs, CDN URL builder
│   ├── socket.ts          # Socket.io server, Redis adapter, geo-rooms
│   ├── broadcast.ts       # Fire-and-forget WebSocket broadcast helpers
│   ├── errors.ts          # HttpError class
│   └── logger.ts          # Pino structured logging
├── middleware/
│   ├── validate.ts        # Zod schema validation
│   ├── request-id.ts      # x-request-id propagation
│   ├── request-logger.ts  # pino-http request logging
│   ├── rate-limit.ts      # IP-based rate limiting (global + write)
│   ├── error-handler.ts   # Centralized error responses
│   └── not-found.ts       # 404 catch-all
├── models/                # Database query functions (raw SQL via pg)
│   ├── report.ts
│   ├── comment.ts
│   ├── media.ts
│   ├── report-upvote.ts
│   ├── comment-flag.ts
│   ├── device-activity.ts
│   └── types.ts           # Shared TypeScript interfaces
├── routes/
│   ├── index.ts           # Mounts /reports and /comments under /api/v1
│   ├── reports.ts         # Report CRUD + comments + media upload
│   ├── comments.ts        # Comment flagging
│   └── health.ts          # Liveness + readiness probes
└── validators/            # Zod schemas
    ├── report.ts
    ├── comment.ts
    └── media.ts
```

**Key design choices:**
- No controller/service/repository layers -- route handlers call model functions directly
- Zod for request validation (body, query, params)
- Raw SQL via `pg` pool (no ORM)
- Pino for JSON-structured logging
- `express-async-errors` for automatic error catching (no try/catch in routes)

## API Endpoints

Base URL: `/api/v1`

### Health

| Method | Path | Description |
|--------|------|-------------|
| GET | `/health` | Liveness probe (always 200 if process is running) |
| GET | `/health/ready` | Readiness probe (checks DB + Redis + Socket.io adapter) |

### Reports

| Method | Path | Description |
|--------|------|-------------|
| POST | `/api/v1/reports` | Create a new crime report |
| GET | `/api/v1/reports` | List reports near a location |
| GET | `/api/v1/reports/:id` | Get a single report with media |
| POST | `/api/v1/reports/:id/upvote` | Toggle upvote on a report |

### Comments

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/v1/reports/:id/comments` | List comments for a report |
| POST | `/api/v1/reports/:id/comments` | Add a comment to a report |
| POST | `/api/v1/comments/:id/flag` | Flag a comment |

### Media Upload

| Method | Path | Description |
|--------|------|-------------|
| POST | `/api/v1/reports/:id/upload` | Get a presigned S3 upload URL |
| POST | `/api/v1/reports/:id/upload/complete` | Confirm upload completion |
| GET | `/api/v1/reports/:id/media/status` | Poll media processing status |

---

## Endpoint Details

### POST /api/v1/reports

Create a new crime report.

**Request body:**
```json
{
  "device_id": "abc123",
  "type": "theft",
  "description": "Bike stolen from rack outside store",
  "lat": 37.775,
  "lng": -122.419,
  "address": "123 Main St"
}
```

| Field | Type | Required | Constraints |
|-------|------|----------|-------------|
| `device_id` | string | yes | 1-64 chars |
| `type` | string | yes | One of: `theft`, `assault`, `vandalism`, `robbery`, `burglary`, `suspicious`, `shooting`, `carjacking`, `harassment`, `drug_activity`, `other` |
| `description` | string | no | Max 2000 chars |
| `lat` | number | yes | -90 to 90 |
| `lng` | number | yes | -180 to 180 |
| `address` | string | no | Max 255 chars |

**Response:** `201 Created`
```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "device_id": "abc123",
  "type": "theft",
  "description": "Bike stolen from rack outside store",
  "location": { "lat": 37.775, "lng": -122.419 },
  "address": "123 Main St",
  "status": "pending",
  "upvotes": 0,
  "comment_count": 0,
  "created_at": "2026-02-27T10:00:00.000Z",
  "updated_at": "2026-02-27T10:00:00.000Z"
}
```

---

### GET /api/v1/reports

List reports near a geographic location using PostGIS.

**Query parameters:**

| Param | Type | Required | Default | Constraints |
|-------|------|----------|---------|-------------|
| `lat` | number | yes | -- | -90 to 90 |
| `lng` | number | yes | -- | -180 to 180 |
| `radius` | number | no | 5000 | 100-50000 (meters) |
| `limit` | integer | no | 20 | 1-100 |
| `offset` | integer | no | 0 | >= 0 |

**Response:** `200 OK`
```json
{
  "data": [
    {
      "id": "...",
      "type": "theft",
      "description": "...",
      "location": { "lat": 37.775, "lng": -122.419 },
      "status": "active",
      "upvotes": 5,
      "comment_count": 2,
      "distance_m": 342.5,
      "created_at": "..."
    }
  ],
  "meta": { "lat": 37.775, "lng": -122.419, "radius": 5000, "limit": 20, "offset": 0, "count": 1 }
}
```

---

### GET /api/v1/reports/:id

Get a single report with its media attachments.

**Response:** `200 OK`
```json
{
  "id": "...",
  "type": "theft",
  "location": { "lat": 37.775, "lng": -122.419 },
  "status": "active",
  "upvotes": 5,
  "comment_count": 2,
  "media": [
    {
      "id": "...",
      "type": "image",
      "url": "https://d111.cloudfront.net/images/report-id/file-id.jpg",
      "thumbnail_url": "https://d111.cloudfront.net/images/report-id/file-id_thumb.jpg",
      "status": "active",
      "width": 1920,
      "height": 1080,
      "created_at": "..."
    }
  ],
  "created_at": "...",
  "updated_at": "..."
}
```

---

### POST /api/v1/reports/:id/upvote

Toggle upvote on a report. Calling again removes the upvote.

**Request body:**
```json
{ "device_id": "abc123" }
```

**Response:** `200 OK`
```json
{ "upvoted": true }
```

---

### GET /api/v1/reports/:id/comments

List comments for a report.

**Query parameters:**

| Param | Type | Default | Constraints |
|-------|------|---------|-------------|
| `limit` | integer | 20 | 1-100 |
| `offset` | integer | 0 | >= 0 |

**Response:** `200 OK`
```json
{
  "data": [
    {
      "id": "...",
      "report_id": "...",
      "device_id": "def456",
      "content": "I saw this happen around 3pm",
      "upvotes": 0,
      "flag_count": 0,
      "created_at": "..."
    }
  ],
  "meta": { "report_id": "...", "limit": 20, "offset": 0, "count": 1 }
}
```

---

### POST /api/v1/reports/:id/comments

Add a comment to a report. Atomically increments the report's `comment_count`.

**Request body:**
```json
{
  "device_id": "def456",
  "content": "I saw this happen around 3pm"
}
```

| Field | Type | Required | Constraints |
|-------|------|----------|-------------|
| `device_id` | string | yes | 1-64 chars |
| `content` | string | yes | 1-1000 chars, whitespace-trimmed |

**Response:** `201 Created`

---

### POST /api/v1/comments/:id/flag

Flag a comment. Each device can only flag a comment once (idempotent).

**Request body:**
```json
{ "device_id": "abc123" }
```

**Response:** `200 OK`
```json
{ "flagged": true }
```

---

### POST /api/v1/reports/:id/upload

Request a presigned S3 URL to upload media for a report. Only the report's creator (matching `device_id`) can upload.

**Request body:**
```json
{
  "device_id": "abc123",
  "file_type": "image",
  "content_type": "image/jpeg"
}
```

| Field | Type | Required | Values |
|-------|------|----------|--------|
| `device_id` | string | yes | 1-64 chars |
| `file_type` | string | yes | `image` or `video` |
| `content_type` | string | yes | `image/jpeg`, `image/png`, `image/webp`, `video/mp4`, `video/quicktime`, `video/webm` |

`content_type` must match `file_type` (e.g., `image/jpeg` requires `file_type: "image"`).

**Response:** `201 Created`
```json
{
  "upload_url": "https://s3.amazonaws.com/bucket/...",
  "media_key": "images/report-id/file-id.jpg",
  "expires_in": 900
}
```

**Upload flow:**
1. Call this endpoint to get `upload_url` and `media_key`
2. `PUT` the file to `upload_url` with the matching `Content-Type` header
3. Call `POST /reports/:id/upload/complete` with the `media_key`

---

### POST /api/v1/reports/:id/upload/complete

Confirm that a file has been uploaded to S3. Verifies the object exists in the uploads bucket, then marks media as `processing`.

**Request body:**
```json
{
  "device_id": "abc123",
  "media_key": "images/report-id/file-id.jpg"
}
```

**Response:** `200 OK`
```json
{ "status": "processing" }
```

Idempotent -- returns current status if already processing or active.

---

### GET /api/v1/reports/:id/media/status

Poll the processing status of all media for a report. Checks S3 buckets to determine whether Step Functions has finished processing.

**Response:** `200 OK`
```json
{
  "status": "active",
  "media": [
    {
      "id": "...",
      "type": "image",
      "url": "https://cdn.example.com/images/report-id/file-id.jpg",
      "thumbnail_url": "https://cdn.example.com/images/report-id/file-id_thumb.jpg",
      "status": "active"
    }
  ]
}
```

**Status values:** `pending` | `uploading` | `processing` | `active` | `failed` | `removed`

---

## WebSocket (Socket.io)

Real-time updates are delivered over Socket.io on the same HTTP server. No separate WebSocket endpoint is needed.

### Connection

```javascript
const socket = io('https://api.example.com', {
  auth: { deviceId: 'your-device-id' }
});
```

Authentication requires a valid `deviceId` (1-64 chars) in `socket.handshake.auth`.

### Client → Server Events

| Event | Payload | Description |
|-------|---------|-------------|
| `subscribe:location` | `{ lat: number, lng: number }` | Join a geo-grid room. Validates lat (-90 to 90) and lng (-180 to 180). |
| `unsubscribe:location` | -- | Leave the current location room |
| `subscribe:report` | `reportId: string` | Watch a specific report for comments/upvotes (max 50 per connection) |
| `unsubscribe:report` | `reportId: string` | Stop watching a report |

### Connection Limits

| Limit | Value |
|-------|-------|
| Max concurrent connections per device | 3 |
| Max report room subscriptions per socket | 50 |

### Server → Client Events

| Event | Payload | When |
|-------|---------|------|
| `report:new` | `{ id, type, lat, lng, description, upvotes, comment_count, created_at }` | A nearby report's media is fully processed and the report becomes `active` |
| `comment:new` | `{ id, report_id, content, created_at }` | A new comment is added to a watched report |
| `report:upvote` | `{ report_id, upvoted }` | An upvote is toggled on a watched report |

### Geo-Grid Rooms

Locations are mapped to a 0.1-degree (~11 km) grid. When a report becomes active, `report:new` is emitted to the report's grid cell and all 8 neighboring cells (3x3 overlap), ensuring users near grid boundaries receive the update.

### Scaling

The `@socket.io/redis-adapter` uses Redis Pub/Sub to synchronize broadcasts across all ECS Fargate tasks, so any server instance can emit to clients connected to any other instance. The adapter connects with TLS in production to match ElastiCache's transit encryption, and uses a 3-attempt retry loop. Its health is reported in the `/health/ready` endpoint.

The adapter connects asynchronously in the background -- the HTTP server starts immediately without waiting for Redis, so ECS health checks pass before the adapter is ready.

---

## Error Responses

All errors follow a consistent format:

```json
{
  "error": "Error message describing what went wrong"
}
```

| Status | Meaning | When |
|--------|---------|------|
| 400 | Bad Request | Validation failed, missing fields, invalid values |
| 403 | Forbidden | Flagged device, unauthorized action, removed report |
| 404 | Not Found | Report/comment/media doesn't exist |
| 409 | Conflict | Report already has media being processed |
| 429 | Too Many Requests | Rate limit exceeded |
| 500 | Internal Server Error | Unexpected server error |

## Rate Limits

### Device-Based Limits

| Action | Limit | Window |
|--------|-------|--------|
| Create reports | 10 per device | Per day |
| Create comments | 50 per device | Per day |
| Media per report | 5 files max | -- |

Flagged devices are blocked from creating reports, comments, and uploading media.

### HTTP Rate Limiting (IP-Based)

Application-level throttling via `express-rate-limit`, complementing AWS WAF (2000 req/5min per IP):

| Scope | Limit | Applied To |
|-------|-------|------------|
| Global | 100 req/min per IP | All `/api/v1` routes |
| Writes | 20 req/min per IP | All POST endpoints |

Both limiters are disabled in development. Returns `429 Too Many Requests` when exceeded.

## Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `NODE_ENV` | no | `development` | `development` or `production` |
| `PORT` | no | `3000` | Server port |
| `CORS_ORIGIN` | no | `*` | Allowed CORS origins |
| `DATABASE_URL` | yes* | -- | PostgreSQL connection string |
| `DB_POOL_MAX` | no | `20` | Max connections in pool |
| `DB_IDLE_TIMEOUT_MS` | no | `30000` | Idle connection timeout |
| `DB_CONNECTION_TIMEOUT_MS` | no | `5000` | Connection timeout |
| `REDIS_HOST` | no | `localhost` | Redis host |
| `REDIS_PORT` | no | `6379` | Redis port |
| `AWS_REGION` | no | `us-east-1` | AWS region |
| `S3_UPLOADS_BUCKET` | yes* | -- | S3 bucket for raw uploads |
| `S3_MEDIA_BUCKET` | yes* | -- | S3 bucket for processed media |
| `CDN_DOMAIN` | yes* | -- | CloudFront domain for CDN URLs |

*Required in production. In development, empty string defaults are used.

## Database Migrations

Migrations use [node-pg-migrate](https://github.com/salsita/node-pg-migrate) and run automatically on container startup via `scripts/migrate.js`.

```bash
# Create a new migration
npm run migrate:create -- my-migration-name

# Run pending migrations
npm run migrate:up

# Roll back the last migration
npm run migrate:down
```

Current migrations:
- `1709000000000_initial-schema.sql` -- Reports, media, comments, device activity tables with PostGIS
- `1709100000000_add-comment-flags.sql` -- Comment flags table and flag_count column
- `1709200000000_add-media-key.sql` -- Media key tracking and status columns

## Docker

```bash
# Build
docker build -t crimereport-api .

# Run
docker run -p 3000:3000 \
  -e DATABASE_URL=postgres://... \
  -e REDIS_HOST=... \
  crimereport-api
```

The Dockerfile uses a multi-stage build (Node 20 Alpine). On startup, it runs pending database migrations before starting the server.

## Testing

```bash
# Run all tests
npm test

# Run with coverage
npx jest --coverage

# Run a specific test file
npx jest src/__tests__/routes/reports.test.ts
```

Tests use Jest + Supertest with mocked database and S3 calls. Test files are in `src/__tests__/` mirroring the source structure.
