# Milestone 23: WebSocket Server

## Goal
Implement Socket.io WebSocket server for real-time updates (new reports, comments, upvotes).

## Dependencies
Requires **Milestone 19** (Redis for pub/sub across Fargate tasks).

## Implementation

### 1. Socket.io Server Setup
```javascript
// backend/src/websocket/index.js

const { Server } = require('socket.io');
const { createAdapter } = require('@socket.io/redis-adapter');
const { redis, getSubscriber } = require('../config/redis');
const logger = require('../utils/logger');
const { validateDeviceToken } = require('./auth');

let io;

async function initWebSocket(httpServer) {
  io = new Server(httpServer, {
    cors: {
      origin: '*', // Restrict in production
      methods: ['GET', 'POST'],
    },
    pingTimeout: 60000,
    pingInterval: 25000,
  });
  
  // Redis adapter for horizontal scaling
  const pubClient = redis();
  const subClient = getSubscriber();
  io.adapter(createAdapter(pubClient, subClient));
  
  // Authentication middleware
  io.use(async (socket, next) => {
    try {
      const deviceId = socket.handshake.auth.deviceId;
      if (!deviceId || deviceId.length < 32) {
        return next(new Error('Invalid device ID'));
      }
      socket.deviceId = deviceId;
      next();
    } catch (error) {
      next(new Error('Authentication failed'));
    }
  });
  
  // Connection handling
  io.on('connection', handleConnection);
  
  logger.info('WebSocket server initialized');
  
  return io;
}

function handleConnection(socket) {
  logger.info(`Client connected: ${socket.id}, device: ${socket.deviceId.substring(0, 8)}...`);
  
  // Join location-based rooms
  socket.on('subscribe:location', (data) => {
    const { lat, lng, radius = 10000 } = data;
    const roomId = getLocationRoom(lat, lng, radius);
    socket.join(roomId);
    socket.currentRoom = roomId;
    logger.debug(`Socket ${socket.id} joined room ${roomId}`);
  });
  
  // Leave location room
  socket.on('unsubscribe:location', () => {
    if (socket.currentRoom) {
      socket.leave(socket.currentRoom);
      socket.currentRoom = null;
    }
  });
  
  // Subscribe to specific report (for comments)
  socket.on('subscribe:report', (reportId) => {
    socket.join(`report:${reportId}`);
  });
  
  socket.on('unsubscribe:report', (reportId) => {
    socket.leave(`report:${reportId}`);
  });
  
  // Disconnect handling
  socket.on('disconnect', (reason) => {
    logger.info(`Client disconnected: ${socket.id}, reason: ${reason}`);
  });
}

// Generate room ID based on location grid
function getLocationRoom(lat, lng, radius) {
  // Create grid cells (roughly 10km squares)
  const gridSize = 0.1; // ~11km at equator
  const gridLat = Math.floor(lat / gridSize) * gridSize;
  const gridLng = Math.floor(lng / gridSize) * gridSize;
  return `location:${gridLat}:${gridLng}:${radius}`;
}

function getIO() {
  return io;
}

module.exports = {
  initWebSocket,
  getIO,
  getLocationRoom,
};
```

### 2. Broadcast Service
```javascript
// backend/src/websocket/broadcastService.js

const { getIO, getLocationRoom } = require('./index');
const logger = require('../utils/logger');

// Broadcast new report to nearby users
function broadcastNewReport(report) {
  const io = getIO();
  if (!io) return;
  
  // Broadcast to all location rooms that might include this report
  const rooms = getOverlappingRooms(report.latitude, report.longitude);
  
  const payload = {
    type: 'NEW_REPORT',
    data: {
      id: report.id,
      type: report.type,
      latitude: report.latitude,
      longitude: report.longitude,
      thumbnailUrl: report.media?.[0]?.thumbnail_url,
      createdAt: report.created_at,
    },
  };
  
  rooms.forEach(room => {
    io.to(room).emit('report:new', payload);
    logger.debug(`Broadcast new report to room ${room}`);
  });
}

// Broadcast new comment to report subscribers
function broadcastNewComment(comment, report) {
  const io = getIO();
  if (!io) return;
  
  const payload = {
    type: 'NEW_COMMENT',
    data: {
      id: comment.id,
      reportId: comment.report_id,
      content: comment.content,
      anonymousId: comment.anonymousId,
      isReporter: comment.isReporter,
      createdAt: comment.created_at,
    },
  };
  
  io.to(`report:${comment.report_id}`).emit('comment:new', payload);
}

// Broadcast upvote update
function broadcastUpvoteUpdate(reportId, upvotes) {
  const io = getIO();
  if (!io) return;
  
  const payload = {
    type: 'UPVOTE_UPDATE',
    data: { reportId, upvotes },
  };
  
  io.to(`report:${reportId}`).emit('report:upvote', payload);
}

// Broadcast media ready (after processing)
function broadcastMediaReady(reportId, media) {
  const io = getIO();
  if (!io) return;
  
  const payload = {
    type: 'MEDIA_READY',
    data: {
      reportId,
      media: {
        id: media.id,
        url: media.url,
        thumbnailUrl: media.thumbnail_url,
        type: media.type,
      },
    },
  };
  
  io.to(`report:${reportId}`).emit('media:ready', payload);
}

// Get all rooms that might contain a location
function getOverlappingRooms(lat, lng) {
  const gridSize = 0.1;
  const rooms = [];
  
  // Include neighboring grid cells
  for (let dLat = -1; dLat <= 1; dLat++) {
    for (let dLng = -1; dLng <= 1; dLng++) {
      const gridLat = Math.floor((lat + dLat * gridSize) / gridSize) * gridSize;
      const gridLng = Math.floor((lng + dLng * gridSize) / gridSize) * gridSize;
      rooms.push(`location:${gridLat}:${gridLng}:10000`);
    }
  }
  
  return [...new Set(rooms)];
}

module.exports = {
  broadcastNewReport,
  broadcastNewComment,
  broadcastUpvoteUpdate,
  broadcastMediaReady,
};
```

### 3. Update Entry Point
```javascript
// backend/src/index.js (updated)

const http = require('http');
const app = require('./app');
const { initDatabase } = require('./config/database');
const { initRedis } = require('./config/redis');
const { initWebSocket } = require('./websocket');
const logger = require('./utils/logger');

const PORT = process.env.PORT || 3000;

async function start() {
  try {
    await initDatabase();
    await initRedis();
    
    const server = http.createServer(app);
    
    // Initialize WebSocket
    await initWebSocket(server);
    
    server.listen(PORT, () => {
      logger.info(`Server running on port ${PORT}`);
    });
    
    // Graceful shutdown
    process.on('SIGTERM', async () => {
      logger.info('SIGTERM received');
      server.close(() => process.exit(0));
    });
  } catch (error) {
    logger.error('Failed to start:', error);
    process.exit(1);
  }
}

start();
```

### 4. Integration with Services
```javascript
// backend/src/services/reportService.js (additions)

const { broadcastNewReport } = require('../websocket/broadcastService');

async function createReport(data) {
  // ... existing code ...
  
  const report = await reportRepository.createWithLocation(data);
  
  // Enrich and broadcast
  const enrichedReport = await getReportById(report.id);
  broadcastNewReport(enrichedReport);
  
  return report;
}
```

```javascript
// backend/src/services/commentService.js (additions)

const { broadcastNewComment } = require('../websocket/broadcastService');

async function createComment(data) {
  // ... existing code ...
  
  const comment = await commentRepository.create(data);
  broadcastNewComment(enrichedComment, report);
  
  return enrichedComment;
}
```

### 5. ALB Sticky Sessions
For WebSocket to work with multiple Fargate tasks, ensure ALB has sticky sessions enabled (done in Milestone 17).

### 6. Client Connection Example
```dart
// Flutter client connection (preview for Milestone 26)
import 'package:socket_io_client/socket_io_client.dart' as IO;

final socket = IO.io('wss://api.reportcrime.app', <String, dynamic>{
  'transports': ['websocket'],
  'auth': {'deviceId': deviceId},
});

socket.on('connect', (_) {
  // Subscribe to location
  socket.emit('subscribe:location', {
    'lat': 37.7749,
    'lng': -122.4194,
    'radius': 10000,
  });
});

socket.on('report:new', (data) {
  // Handle new report
  print('New report nearby: ${data['data']['id']}');
});
```

## WebSocket Events

| Event | Direction | Description |
|-------|-----------|-------------|
| `subscribe:location` | Client → Server | Join location room |
| `unsubscribe:location` | Client → Server | Leave location room |
| `subscribe:report` | Client → Server | Watch specific report |
| `report:new` | Server → Client | New report in area |
| `comment:new` | Server → Client | New comment on report |
| `report:upvote` | Server → Client | Upvote count changed |
| `media:ready` | Server → Client | Video processing complete |

## Deliverable Checklist
- [ ] Socket.io server initialized with HTTP server
- [ ] Redis adapter for multi-task scaling
- [ ] Client authentication via device ID
- [ ] Location-based room subscriptions
- [ ] Report-specific room subscriptions
- [ ] `report:new` broadcasts to nearby users
- [ ] `comment:new` broadcasts to report watchers
- [ ] `report:upvote` broadcasts update
- [ ] `media:ready` notifies when video processed
- [ ] Reconnection handling works
- [ ] Load tested with multiple connections

## Files (4 total)
1. `backend/src/websocket/index.js` - Create
2. `backend/src/websocket/broadcastService.js` - Create
3. `backend/src/index.js` - Update
4. `backend/src/services/*.js` - Update to broadcast
