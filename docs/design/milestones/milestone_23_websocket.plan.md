# Milestone 23: WebSocket Server

## Status
Completed

## Goal
Add real-time functionality to the existing HTTP server via Socket.io. Clients receive live updates when new reports, comments, or upvotes occur nearby. Uses the Redis adapter so broadcasts work across multiple Fargate tasks.

## Dependencies
- **Milestone 19** – Redis ElastiCache (pub/sub across tasks)
- **Milestone 17** – ECS Fargate with ALB sticky sessions

## What Was Implemented

### 1. Socket.io Server with Redis Adapter (`backend/api/src/lib/socket.ts`)

Dedicated module that configures the `io` instance with the Redis adapter and all event handling.

- **Redis adapter**: Creates separate pub/sub clients via `@socket.io/redis-adapter` so broadcasts propagate across all ECS tasks. Connects with TLS in production (`tls: config.isProd`) to match ElastiCache's transit encryption. Falls back gracefully to in-memory if Redis is unavailable (local dev).
- **Redis adapter resilience**: Connection uses a retry loop (3 attempts, 2s delay). On failure, `redisAdapterHealthy` is set to `false` and surfaced via `isRedisAdapterHealthy()` in the `/health/ready` endpoint.
- **Non-blocking startup**: `initSocket()` is synchronous -- it registers middleware and event handlers, then fires `connectRedisAdapter()` in the background. The HTTP server starts listening immediately without waiting for the adapter.
- **Auth middleware**: Validates `deviceId` from `socket.handshake.auth` (1-64 chars).
- **Connection limit**: Max 3 concurrent WebSocket connections per device (`MAX_CONNECTIONS_PER_DEVICE`). Tracked via an in-memory `Map<deviceId, count>` decremented on disconnect.
- **Geo-grid rooms**: `subscribe:location` validates lat/lng types and ranges (-90/90, -180/180) before mapping to a 0.1-degree (~11 km) grid cell. Old room is left before joining the new one.
- **Report-specific rooms**: `subscribe:report` joins `report:{id}` for comments/upvotes. Capped at 50 rooms per socket (`MAX_REPORT_ROOMS`).
- **Exported helpers**: `locationRoom(lat, lng)`, `overlappingRooms(lat, lng)` (3x3 neighbor cells), `getIO()`, `shutdownSocket()`, `isRedisAdapterHealthy()`.

### 2. Broadcast Helpers (`backend/api/src/lib/broadcast.ts`)

Fire-and-forget functions called from route handlers after mutations. Each is wrapped in try/catch so a Socket.io failure never blocks the HTTP response.

| Function | Event | Target |
|----------|-------|--------|
| `broadcastNewReport(report)` | `report:new` | All overlapping geo-grid rooms |
| `broadcastNewComment(comment)` | `comment:new` | Report-specific room |
| `broadcastUpvote(reportId, upvoted)` | `report:upvote` | Report-specific room |

### 3. Updated Entry Point (`backend/api/src/index.ts`)

- Calls `initSocket(httpServer)` synchronously, then `httpServer.listen()`. The Redis adapter connects in the background so the server answers health checks immediately.
- Graceful shutdown calls `shutdownSocket()` first, then `httpServer.close()`, then pg pool, then Redis.

### 3b. HTTP Rate Limiting (`backend/api/src/middleware/rate-limit.ts`)

Application-level rate limiting via `express-rate-limit` (complements AWS WAF's IP-based 2000 req/5min rule):

- **Global limiter**: 100 requests/min per IP on all `/api/v1` routes.
- **Write limiter**: 20 requests/min per IP on all POST endpoints (reports, comments, upvotes, uploads, flags).
- Both are skipped in development (`config.isDev`).

### 3c. Health Check Update (`backend/api/src/routes/health.ts`)

`/health/ready` now checks three services: DB, Redis, and the Socket.io Redis adapter (`isRedisAdapterHealthy()`). Returns `socketAdapter: connected | disconnected` in the response.

### 4. Broadcast Integration in Route Handlers (`backend/api/src/routes/reports.ts`)

- **`POST /:id/upvote`** — `broadcast.broadcastUpvote(id, upvoted)` after toggle.
- **`POST /:id/comments`** — `broadcast.broadcastNewComment(comment)` after creation.
- **`GET /:id/media/status`** — `broadcast.broadcastNewReport(report)` when all media transitions to `active` and `report.status` was not already `active` (prevents double broadcast).

### 5. Active-Only Feed (`backend/api/src/models/report.ts`)

`findNearby` query updated from `status != 'removed'` to `status = 'active'`. Only reports with fully processed media appear in the REST feed, consistent with the WebSocket behavior.

### 6. Tests

- `src/__tests__/lib/socket.test.ts` — Unit tests for `locationRoom` and `overlappingRooms` grid math (negative coords, boundary snapping, deduplication).
- `src/__tests__/lib/broadcast.test.ts` — Unit tests for all three broadcast functions (mock `getIO`, verify `.to().emit()` calls, verify fire-and-forget error handling, verify `device_id` is excluded from `comment:new` payload).
- Existing route tests updated to mock `lib/broadcast` so they don't throw.

## WebSocket Events

| Event | Direction | Description |
|-------|-----------|-------------|
| `subscribe:location` | Client → Server | Join a geo-grid room |
| `unsubscribe:location` | Client → Server | Leave geo-grid room |
| `subscribe:report` | Client → Server | Watch a specific report for comments/upvotes |
| `unsubscribe:report` | Client → Server | Stop watching a report |
| `report:new` | Server → Client | New report activated (media processed) in nearby area |
| `comment:new` | Server → Client | New comment on a watched report |
| `report:upvote` | Server → Client | Upvote toggled on a watched report |

## Design Decisions

- **Broadcast after media ready**: `report:new` only broadcasts when media processing completes (status → `active` in the media status polling endpoint). Reports without approved media never appear on other users' feeds/maps.
- **Double broadcast prevention**: Guarded by `report.status !== 'active'` so only the first poll request to see the transition fires the event.
- **Active-only feed**: `findNearby` query uses `status = 'active'` so REST consumers also only see reports with approved media.
- **Media required**: Text-only reports are not broadcast. Every report must complete the media upload + processing pipeline to become visible.
- **Fire-and-forget**: All broadcast calls are wrapped in try/catch. Socket.io failures are logged but never block the HTTP response.

## Files Changed

| File | Action | Purpose |
|------|--------|---------|
| `backend/api/src/lib/socket.ts` | Created | Socket.io init, Redis adapter (TLS, retry, health), auth, connection limit, rooms with validation and caps |
| `backend/api/src/lib/broadcast.ts` | Created | Broadcast helper functions |
| `backend/api/src/lib/redis.ts` | Updated | Added `tls: config.isProd` for ElastiCache transit encryption |
| `backend/api/src/middleware/rate-limit.ts` | Created | Global (100/min) and write (20/min) rate limiters |
| `backend/api/src/index.ts` | Updated | Non-blocking `initSocket()`, updated shutdown order |
| `backend/api/src/app.ts` | Updated | Integrated `globalLimiter` on `/api/v1` |
| `backend/api/src/routes/reports.ts` | Updated | Added broadcast calls and `writeLimiter` on POST routes |
| `backend/api/src/routes/comments.ts` | Updated | Added `writeLimiter` on POST flag route |
| `backend/api/src/routes/health.ts` | Updated | Added `socketAdapter` to readiness check |
| `backend/api/src/models/report.ts` | Updated | `findNearby` filters `status = 'active'` |
| `backend/api/src/__tests__/lib/socket.test.ts` | Created | Grid math unit tests |
| `backend/api/src/__tests__/lib/broadcast.test.ts` | Created | Broadcast function unit tests |
| `backend/api/src/__tests__/routes/reports.test.ts` | Updated | Added broadcast/socket mocks |
| `backend/api/src/__tests__/routes/comments.test.ts` | Updated | Added broadcast/socket mocks |
| `backend/api/src/__tests__/routes/media-upload.test.ts` | Updated | Added broadcast/socket mocks |
| `backend/api/src/__tests__/routes/health.test.ts` | Updated | Added `socketAdapter` assertions |
| `backend/api/package.json` | Updated | Added `@socket.io/redis-adapter`, `express-rate-limit` |

## Notes
- The Redis adapter creates its own pub/sub clients separate from the application Redis client in `lib/redis.ts`. Both use `tls: config.isProd` for ElastiCache transit encryption.
- Grid size of 0.1° (~11 km). Overlapping 3×3 neighbor cells ensures reports at grid boundaries are broadcast to nearby rooms.
- No new HTTP endpoints — all real-time communication uses Socket.io on the existing HTTP server.
- The server starts listening immediately. The Redis adapter connects asynchronously in the background so ECS health checks pass before the adapter is ready. If the adapter fails, the readiness endpoint reports `degraded` but the container stays alive.
