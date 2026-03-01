# Milestone 23: WebSocket Server

## Status
Not Started

## Goal
Add real-time functionality to the existing HTTP server via Socket.io. Clients receive live updates when new reports, comments, or upvotes occur nearby. Uses the Redis adapter so broadcasts work across multiple Fargate tasks.

## Dependencies
- **Milestone 19** – Redis ElastiCache (pub/sub across tasks)
- **Milestone 17** – ECS Fargate with ALB sticky sessions
- Socket.io is already imported in `backend/api/src/index.ts` with a basic connection handler; this milestone fully configures it.

## Plan

### 1. Add Redis Adapter to Socket.io (`backend/api/src/lib/socket.ts`)

Create a dedicated module that configures the `io` instance with the Redis adapter and all event handling. The existing `index.ts` will import this instead of setting up Socket.io inline.

```typescript
// backend/api/src/lib/socket.ts

import { Server as SocketServer, Socket } from 'socket.io';
import { createAdapter } from '@socket.io/redis-adapter';
import { createClient } from 'redis';
import { config } from '../config';
import { logger } from './logger';

let io: SocketServer | null = null;

const GRID_SIZE = 0.1; // ~11 km at the equator

export function getIO(): SocketServer {
  if (!io) throw new Error('Socket.io not initialised');
  return io;
}

export async function initSocket(httpServer: import('http').Server): Promise<SocketServer> {
  io = new SocketServer(httpServer, {
    cors: { origin: config.corsOrigin, methods: ['GET', 'POST'] },
    pingTimeout: 60_000,
    pingInterval: 25_000,
  });

  const pubClient = createClient({
    socket: { host: config.redis.host, port: config.redis.port },
  });
  const subClient = pubClient.duplicate();

  await Promise.all([pubClient.connect(), subClient.connect()]);
  io.adapter(createAdapter(pubClient, subClient));
  logger.info('socket.io redis adapter attached');

  io.use(authMiddleware);
  io.on('connection', handleConnection);

  return io;
}

function authMiddleware(socket: Socket, next: (err?: Error) => void) {
  const deviceId = socket.handshake.auth?.deviceId as string | undefined;
  if (!deviceId || deviceId.length < 1 || deviceId.length > 64) {
    return next(new Error('Invalid device ID'));
  }
  socket.data.deviceId = deviceId;
  next();
}

function handleConnection(socket: Socket) {
  logger.info({ socketId: socket.id, deviceId: socket.data.deviceId }, 'ws client connected');

  socket.on('subscribe:location', (data: { lat: number; lng: number; radius?: number }) => {
    const room = locationRoom(data.lat, data.lng, data.radius ?? 10_000);
    socket.join(room);
    socket.data.locationRoom = room;
    logger.debug({ socketId: socket.id, room }, 'joined location room');
  });

  socket.on('unsubscribe:location', () => {
    if (socket.data.locationRoom) {
      socket.leave(socket.data.locationRoom);
      socket.data.locationRoom = null;
    }
  });

  socket.on('subscribe:report', (reportId: string) => {
    socket.join(`report:${reportId}`);
  });

  socket.on('unsubscribe:report', (reportId: string) => {
    socket.leave(`report:${reportId}`);
  });

  socket.on('disconnect', (reason) => {
    logger.info({ socketId: socket.id, reason }, 'ws client disconnected');
  });
}

export function locationRoom(lat: number, lng: number, radius: number): string {
  const gridLat = Math.floor(lat / GRID_SIZE) * GRID_SIZE;
  const gridLng = Math.floor(lng / GRID_SIZE) * GRID_SIZE;
  return `location:${gridLat}:${gridLng}:${radius}`;
}

export function overlappingRooms(lat: number, lng: number): string[] {
  const rooms = new Set<string>();
  for (let dLat = -1; dLat <= 1; dLat++) {
    for (let dLng = -1; dLng <= 1; dLng++) {
      const gridLat = Math.floor((lat + dLat * GRID_SIZE) / GRID_SIZE) * GRID_SIZE;
      const gridLng = Math.floor((lng + dLng * GRID_SIZE) / GRID_SIZE) * GRID_SIZE;
      rooms.add(`location:${gridLat}:${gridLng}:10000`);
    }
  }
  return [...rooms];
}
```

### 2. Broadcast Helper (`backend/api/src/lib/broadcast.ts`)

Thin helper functions that route handlers call after mutations. Each function is fire-and-forget so the HTTP response is never delayed.

```typescript
// backend/api/src/lib/broadcast.ts

import { getIO, overlappingRooms } from './socket';
import { logger } from './logger';

export function broadcastNewReport(report: {
  id: string;
  type: string;
  lat: number;
  lng: number;
  created_at: Date;
}) {
  try {
    const io = getIO();
    const rooms = overlappingRooms(report.lat, report.lng);
    const payload = {
      id: report.id,
      type: report.type,
      lat: report.lat,
      lng: report.lng,
      created_at: report.created_at,
    };
    for (const room of rooms) {
      io.to(room).emit('report:new', payload);
    }
  } catch (err) {
    logger.error({ err }, 'broadcast report:new failed');
  }
}

export function broadcastNewComment(comment: {
  id: string;
  report_id: string;
  device_id: string;
  content: string;
  created_at: Date;
}) {
  try {
    const io = getIO();
    io.to(`report:${comment.report_id}`).emit('comment:new', {
      id: comment.id,
      report_id: comment.report_id,
      content: comment.content,
      created_at: comment.created_at,
    });
  } catch (err) {
    logger.error({ err }, 'broadcast comment:new failed');
  }
}

export function broadcastUpvote(reportId: string, upvoted: boolean) {
  try {
    const io = getIO();
    io.to(`report:${reportId}`).emit('report:upvote', { report_id: reportId, upvoted });
  } catch (err) {
    logger.error({ err }, 'broadcast report:upvote failed');
  }
}

export function broadcastMediaReady(reportId: string, media: {
  id: string;
  url: string;
  thumbnail_url: string | null;
  type: string;
}) {
  try {
    const io = getIO();
    io.to(`report:${reportId}`).emit('media:ready', { report_id: reportId, ...media });
  } catch (err) {
    logger.error({ err }, 'broadcast media:ready failed');
  }
}
```

### 3. Update Entry Point (`backend/api/src/index.ts`)

Replace the inline Socket.io setup with the new `initSocket` function. The HTTP server and graceful shutdown logic stay the same.

```typescript
// backend/api/src/index.ts (updated)

import { createServer } from 'http';
import app from './app';
import { config } from './config';
import { pool } from './lib/db';
import { disconnect as disconnectRedis } from './lib/redis';
import { logger } from './lib/logger';
import { initSocket } from './lib/socket';

const httpServer = createServer(app);

(async () => {
  const io = await initSocket(httpServer);

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
})();

export { app, httpServer };
```

### 4. Integrate Broadcasts into Route Handlers

Add broadcast calls to the existing route handlers in `backend/api/src/routes/reports.ts`. No service layer or controller class needed — the broadcasts are one-liners added after the database mutation.

```typescript
// In backend/api/src/routes/reports.ts — add import at the top:
import * as broadcast from '../lib/broadcast';

// After creating a report (inside the POST / handler):
router.post('/', validate(createReportSchema), async (req: Request, res: Response) => {
  // ... existing device checks and create logic ...
  const report = await reportModel.create({ device_id, type, description, lat, lng, address });
  await deviceActivity.incrementReportCount(device_id);

  broadcast.broadcastNewReport(report);

  res.status(201).json(report);
});

// After toggling an upvote (inside the POST /:id/upvote handler):
router.post('/:id/upvote', validate(upvoteSchema), async (req: Request, res: Response) => {
  // ... existing logic ...
  const upvoted = await upvoteModel.toggle(id, device_id);

  broadcast.broadcastUpvote(id, upvoted);

  res.json({ upvoted });
});

// After creating a comment (inside the POST /:id/comments handler):
router.post('/:id/comments', validate(createCommentSchema), async (req: Request, res: Response) => {
  // ... existing logic ...
  const comment = await commentModel.createForReport({ report_id: id, device_id, content });

  broadcast.broadcastNewComment(comment);

  res.status(201).json(comment);
});
```

### 5. ALB Sticky Sessions

WebSocket long-polling fallback requires sticky sessions on the ALB target group. The ECS/Fargate stack (Milestone 17) should enable `stickiness` on the target group with a duration of 86 400 s. Once the WebSocket upgrade completes, the TCP connection stays pinned regardless of stickiness settings.

### 6. Client Connection Example (Flutter Preview)

```dart
import 'package:socket_io_client/socket_io_client.dart' as IO;

final socket = IO.io('wss://api.reportcrime.app', <String, dynamic>{
  'transports': ['websocket'],
  'auth': {'deviceId': deviceId},
});

socket.on('connect', (_) {
  socket.emit('subscribe:location', {
    'lat': 37.7749,
    'lng': -122.4194,
    'radius': 10000,
  });
});

socket.on('report:new', (data) => print('New report: ${data['id']}'));
socket.on('comment:new', (data) => print('New comment: ${data['id']}'));
socket.on('report:upvote', (data) => print('Upvote: ${data['report_id']}'));
```

## WebSocket Events

| Event | Direction | Description |
|-------|-----------|-------------|
| `subscribe:location` | Client → Server | Join a geo-grid room |
| `unsubscribe:location` | Client → Server | Leave geo-grid room |
| `subscribe:report` | Client → Server | Watch a specific report for comments/upvotes |
| `unsubscribe:report` | Client → Server | Stop watching a report |
| `report:new` | Server → Client | New report created in nearby area |
| `comment:new` | Server → Client | New comment on a watched report |
| `report:upvote` | Server → Client | Upvote toggled on a watched report |
| `media:ready` | Server → Client | Media processing complete for a report |

## API Endpoints
No new HTTP endpoints. All real-time communication uses the Socket.io WebSocket transport on the existing HTTP server.

## Testing Plan
- Unit tests for `locationRoom` and `overlappingRooms` grid math
- Unit tests for each `broadcast.*` function (mock `getIO`, verify `.to().emit()` calls)
- Integration test: connect two Socket.io clients, subscribe one to a location room, create a report via HTTP, assert the subscribed client receives `report:new`
- Integration test: subscribe to a report room, post a comment, assert `comment:new` received
- Integration test: verify auth middleware rejects connections with missing/invalid device ID
- Load test: 500+ concurrent connections with Redis adapter across 2 server instances

## Notes
- The Redis adapter creates its own pub/sub clients separate from the application Redis client in `lib/redis.ts`. This avoids blocking the main client with `SUBSCRIBE`.
- Grid size of 0.1° (~11 km) is a reasonable default. Overlapping 3×3 neighbor cells ensures a report at a grid boundary is still broadcast to nearby rooms.
- `broadcast.*` calls are fire-and-forget inside route handlers. A Socket.io failure never blocks the HTTP response.
- The `@socket.io/redis-adapter` package must be added to `package.json`.

## Files (3 new, 2 updated)
1. `backend/api/src/lib/socket.ts` – **Create** – Socket.io init, Redis adapter, auth, rooms
2. `backend/api/src/lib/broadcast.ts` – **Create** – Broadcast helper functions
3. `backend/api/src/index.ts` – **Update** – Replace inline Socket.io setup with `initSocket`
4. `backend/api/src/routes/reports.ts` – **Update** – Add `broadcast.*` calls after mutations
5. `backend/api/package.json` – **Update** – Add `@socket.io/redis-adapter` dependency
