# WebSockets & Real-Time Updates - Knowledge Base

Personal reference notes for understanding the real-time layer in the CrimeReport project.

*Server code: [backend/api/src/lib/socket.ts](../../backend/api/src/lib/socket.ts) (Milestone 23)*
*Flutter client: [apps/mobile/lib/](../../apps/mobile/lib/) (Milestone 26)*

---

## The Problem

Without real-time updates, the app has two bad options:

1. **Manual refresh** -- the user pulls down to reload. They only see new reports when they actively check. A crime could happen next door and they wouldn't know until they open the app and refresh.

2. **Polling** -- the app automatically hits the API every few seconds ("anything new? anything new?"). This works, but:
   - Wastes battery and data -- most requests return nothing
   - Adds load to the server -- thousands of devices asking every 5 seconds
   - Still not instant -- there's always a delay equal to the poll interval

The real-time approach flips this around: the server **pushes** updates to the client the moment something happens. Zero wasted requests, instant delivery.

---

## What Is a WebSocket?

A normal HTTP request is like sending a letter:

```
Client: "GET /reports" → Server processes → Server: "Here's the data" → Connection closed
```

Each request opens a connection, gets a response, and closes. The server has no way to reach back out to the client later.

A WebSocket is like a phone call:

```
Client: "Let's upgrade to WebSocket" → Server: "OK, upgraded"
    ↕ Connection stays open ↕
Client can send messages anytime
Server can send messages anytime
    ↕ Until one side hangs up ↕
```

The connection starts as a normal HTTP request (called the "handshake" or "upgrade"), then upgrades to a persistent two-way channel. Both sides can send data at any time without opening new connections.

### WebSocket vs HTTP Comparison

| | HTTP | WebSocket |
|--|------|-----------|
| **Connection** | Opens and closes per request | Stays open |
| **Direction** | Client initiates, server responds | Both sides can send anytime |
| **Overhead** | Full HTTP headers on every request | Tiny frame headers after handshake |
| **Server push** | Not possible (server can't reach client) | Server pushes whenever it wants |
| **Use case** | CRUD operations, page loads | Live feeds, chat, notifications |

### The Upgrade Process

```
1. Client sends HTTP request with special headers:
   GET /socket.io/?transport=websocket HTTP/1.1
   Upgrade: websocket
   Connection: Upgrade

2. Server responds with 101 Switching Protocols:
   HTTP/1.1 101 Switching Protocols
   Upgrade: websocket
   Connection: Upgrade

3. From this point, the TCP connection stays open
   and both sides speak the WebSocket protocol
   (binary frames, not HTTP)
```

In our architecture, the ALB (Application Load Balancer) handles this upgrade transparently. It sees the `Upgrade: websocket` header and maintains the connection to the Fargate task.

---

## Why Socket.io Instead of Raw WebSockets

Socket.io is a library that wraps WebSockets with useful features:

### Auto-Reconnection

If the user walks into an elevator and loses signal, a raw WebSocket would die and stay dead. Socket.io automatically retries with exponential backoff:

```
Connection lost → retry in 1s → retry in 2s → retry in 4s → ... → connected!
```

The app doesn't need to handle reconnection logic.

### Fallback Transport

Some corporate WiFi networks and firewalls block WebSocket connections. Socket.io can fall back to **HTTP long-polling** (client holds an HTTP request open, server responds when there's data, client immediately opens another). The API is identical -- your code doesn't need to know which transport is being used.

### Rooms

This is the key feature for our app. Socket.io lets you group connections into named "rooms" and broadcast to an entire room at once:

```
Room "location:37.7:-122.4:10000"
├── User A's socket
├── User B's socket
└── User C's socket

io.to("location:37.7:-122.4:10000").emit("report:new", data)
→ All three users receive the event simultaneously
```

Without rooms, you'd have to loop through every connected socket, check their location, and decide whether to send them the event. Rooms make this a one-liner.

### Namespaces (Not Used Yet)

Socket.io supports "namespaces" -- separate communication channels on the same connection. We could use `/feed` and `/map` namespaces in the future, but for MVP a single default namespace is simpler.

---

## How Rooms Work in Our App

We use two types of rooms:

### 1. Location Rooms (Geo-Grid)

When a user opens the app, they subscribe to updates near their location. But we can't create a separate room for every unique lat/lng coordinate -- there'd be millions of rooms with one user each.

Instead, we divide the world into a **grid** of 0.1-degree cells (~11km squares):

```
         -122.5    -122.4    -122.3
          │          │          │
37.8 ─────┼──────────┼──────────┼─────
          │          │          │
          │  Cell A  │  Cell B  │
          │          │          │
37.7 ─────┼──────────┼──────────┼─────
          │          │          │
          │  Cell C  │  Cell D  │
          │          │          │
37.6 ─────┼──────────┼──────────┼─────
```

A user at (37.75, -122.42) falls into Cell A. Their room name is `location:37.7:-122.5:10000`.

The grid cell is calculated by flooring to the nearest 0.1:

```typescript
const gridLat = Math.floor(lat / 0.1) * 0.1;  // 37.75 → 37.7
const gridLng = Math.floor(lng / 0.1) * 0.1;  // -122.42 → -122.5
```

### The Border Problem

What if a report happens right at the edge between Cell A and Cell C? A user in Cell A wouldn't receive it, even though it's only 100 meters away.

Solution: when broadcasting a new report, we emit to the **3x3 grid of neighboring cells** around the report's location:

```
┌──────────┬──────────┬──────────┐
│ NW cell  │ N cell   │ NE cell  │
├──────────┼──────────┼──────────┤
│ W cell   │ CENTER   │ E cell   │
├──────────┼──────────┼──────────┤
│ SW cell  │ S cell   │ SE cell  │
└──────────┴──────────┴──────────┘

Report at (37.75, -122.42) → broadcast to all 9 cells
```

This means a report is always broadcast to an area roughly 33km x 33km, ensuring no one near a border misses it. The overlap is intentional -- receiving an extra notification that you filter out on the client is much better than missing a nearby report.

### 2. Report Rooms

When a user taps into a specific report (to read comments or watch the video), the client subscribes to `report:{id}`:

```
Room "report:550e8400-..."
├── User viewing the report's comments
├── Another user watching the video
└── User who just opened the report
```

This room receives `comment:new`, `report:upvote`, and `media:ready` events. Only people actively looking at that report get these updates -- not everyone nearby.

---

## The Redis Adapter: Cross-Task Broadcasting

### The Problem

In production, we run multiple copies of the API server (Fargate tasks) for reliability and scaling. Each task has its own Socket.io instance in memory:

```
Task 1 (Socket.io)          Task 2 (Socket.io)
├── User A's socket          ├── User C's socket
└── User B's socket          └── User D's socket
```

If User A creates a report, Task 1's Socket.io broadcasts it. But Task 1 only knows about Users A and B. Users C and D on Task 2 never hear about it.

### The Solution: Redis Pub/Sub

The `@socket.io/redis-adapter` makes all tasks share the same "room state" via Redis:

```
Task 1: io.to("location:37.7:...").emit("report:new", data)
  │
  ├── Emits directly to local sockets (Users A, B) that are in the room
  │
  └── Publishes to Redis channel: "socket.io#/#location:37.7:..."
         │
         └── Redis fans out to all subscribers
                │
                └── Task 2 receives → emits to local sockets (Users C, D) in the room
```

From the developer's perspective, nothing changes. You still call `io.to(room).emit(event, data)` and the adapter handles the cross-task delivery transparently.

### How Redis Pub/Sub Works

Redis pub/sub is a messaging pattern:

```
Publisher                    Redis                     Subscriber
    │                          │                           │
    │── PUBLISH channel msg ──►│                           │
    │                          │── delivers msg ──────────►│
    │                          │── delivers msg ──────────►│ (other subscriber)
```

- **SUBSCRIBE**: A client listens to a channel. It blocks and waits for messages.
- **PUBLISH**: A client sends a message to a channel. All subscribers receive it instantly.

The Socket.io adapter creates two dedicated Redis connections:
- **pubClient**: Publishes broadcast messages
- **subClient**: Subscribes to receive broadcasts from other tasks

These are separate from the application's Redis client (`lib/redis.ts`) because a subscribed Redis connection can't do normal commands (GET, SET, etc.) -- it's blocked in subscription mode.

---

## Event Flow: Complete Example

Let's trace what happens when User A creates a report, and User B (on a different server) sees it appear on their map:

```
1. User A's phone
   POST /api/v1/reports { type: "theft", lat: 37.77, lng: -122.41 }
         │
         ▼
2. ALB routes to Task 1
         │
         ▼
3. Express route handler (routes/reports.ts)
   - Validates request (Zod)
   - Checks device not flagged
   - Checks rate limit
   - INSERT INTO reports ... (PostgreSQL)
   - Returns 201 to User A
   - Calls broadcast.broadcastNewReport(report)  ← fire-and-forget
         │
         ▼
4. broadcast.ts → broadcastNewReport()
   - Calculates overlapping grid cells for (37.77, -122.41)
   - Calls io.to("location:37.7:-122.5:10000").emit("report:new", {...})
   - Also emits to 8 neighboring grid cells
         │
         ▼
5. Socket.io Redis Adapter (on Task 1)
   - Emits to local sockets in those rooms (if any)
   - Publishes message to Redis pub/sub channel
         │
         ▼
6. Redis (ElastiCache)
   - Receives PUBLISH
   - Fans out to all subscribed tasks
         │
         ▼
7. Socket.io Redis Adapter (on Task 2)
   - Receives message from Redis subscription
   - Checks which local sockets are in the matching rooms
   - User B is in room "location:37.7:-122.5:10000"
         │
         ▼
8. Task 2 sends WebSocket frame to User B
         │
         ▼
9. User B's phone
   - socket_io_client receives "report:new" event
   - App adds the report to the feed list
   - App adds a marker to the map
   - User B sees the new crime appear instantly
```

Total latency: typically **50-200ms** from database insert to the other user's screen.

---

## Connection Lifecycle

### Normal Flow

```
App opens
  → socket.connect()
  → Handshake + upgrade to WebSocket
  → Client sends "subscribe:location" with lat/lng
  → Server joins client to geo-grid room
  → Client receives events as they happen

User opens a specific report
  → Client sends "subscribe:report" with report ID
  → Server joins client to report room
  → Client receives comment/upvote events for that report

User navigates away from the report
  → Client sends "unsubscribe:report"
  → Server removes client from report room

App goes to background
  → Connection stays open briefly, then times out
  → Socket.io client detects disconnect

App returns to foreground
  → Socket.io client automatically reconnects
  → Client re-sends "subscribe:location"
  → Missed events during background? Client fetches fresh data via REST API
```

### Handling Disconnections

Socket.io handles reconnection automatically with exponential backoff. But there's a window where events can be missed (between disconnect and reconnect). The strategy:

1. On reconnect, the client re-subscribes to its rooms
2. The client also does a REST API fetch to get any data it missed
3. The REST response is the source of truth; WebSocket events are for instant updates between fetches

This means the app is always eventually consistent -- WebSocket makes it feel instant, REST makes it correct.

---

## Authentication

Our WebSocket connections use a simple device ID check (consistent with the REST API's anonymous model):

```typescript
// Server-side auth middleware
function authMiddleware(socket, next) {
  const deviceId = socket.handshake.auth?.deviceId;
  if (!deviceId || deviceId.length < 1 || deviceId.length > 64) {
    return next(new Error('Invalid device ID'));
  }
  socket.data.deviceId = deviceId;
  next();
}
```

The client passes `deviceId` during the handshake:

```dart
// Flutter client
final socket = IO.io(url, {
  'auth': {'deviceId': hashedDeviceId},
});
```

No JWT tokens or session cookies -- matches our fully anonymous design.

---

## Fire-and-Forget Pattern

All broadcast calls in route handlers are wrapped in try/catch:

```typescript
export function broadcastNewReport(report) {
  try {
    const io = getIO();
    const rooms = overlappingRooms(report.lat, report.lng);
    for (const room of rooms) {
      io.to(room).emit('report:new', payload);
    }
  } catch (err) {
    logger.error({ err }, 'broadcast report:new failed');
  }
}
```

If Socket.io is down, the Redis adapter fails, or anything goes wrong:
- The broadcast silently fails and logs the error
- The HTTP response still goes through normally
- The report is still saved to the database
- Users will see it on their next REST API fetch

Real-time updates are a **nice-to-have enhancement**, not a critical dependency. The app must work correctly even if WebSocket is completely broken.

---

## Socket.io vs Alternatives

| Technology | Pros | Cons | Why Not |
|-----------|------|------|---------|
| **Socket.io** | Auto-reconnect, rooms, Redis adapter, fallback transport | Slight overhead vs raw WS | -- (our choice) |
| Raw WebSocket | Lighter, no dependencies | Manual reconnect, no rooms, no fallback, no scaling adapter | Too much to build ourselves |
| Firebase Realtime DB | Easy setup, offline sync | Vendor lock-in, no geo queries, costs scale poorly | Doesn't fit our AWS stack |
| AWS AppSync | GraphQL subscriptions, managed | Complex, overkill for our use case | Adds unnecessary complexity |
| Server-Sent Events (SSE) | Simple, HTTP-based | One-direction only (server→client), no rooms | We need client→server too (subscribe) |
| Pusher / Ably | Managed WebSocket service | Monthly costs, external dependency | Prefer self-hosted for control |

---

## Performance Considerations

### Connection Limits

Each Fargate task can handle thousands of concurrent WebSocket connections. The limiting factor is usually memory (each connection uses ~10-50KB of RAM). With 512MB tasks, expect ~5,000-10,000 connections per task.

### ALB and WebSockets

The Application Load Balancer supports WebSocket natively. Once the HTTP upgrade completes, the ALB maintains the TCP connection to the specific Fargate task. There's a default idle timeout of 60 seconds -- if no data flows for 60 seconds, ALB closes the connection. Socket.io's ping/pong mechanism (every 25 seconds) keeps the connection alive.

### Sticky Sessions

For the initial HTTP handshake and long-polling fallback, the ALB needs **sticky sessions** so subsequent requests from the same client go to the same task. Once the WebSocket upgrade completes, stickiness doesn't matter (the TCP connection is already pinned). We configure stickiness on the ALB target group as a safety measure.

### Redis Adapter Overhead

Each broadcast adds a Redis PUBLISH command (~0.1ms). With thousands of broadcasts per second, Redis handles this easily -- pub/sub is one of Redis's fastest operations. The adapter adds roughly 1-5ms of latency compared to local-only broadcasting.

---

## Our Implementation (Milestone 23 Server, Milestone 26 Flutter Client)

### Server Side (Milestone 23)

| File | Purpose |
|------|---------|
| `backend/api/src/lib/socket.ts` | Socket.io init, Redis adapter, auth, room management |
| `backend/api/src/lib/broadcast.ts` | Fire-and-forget broadcast helpers |
| `backend/api/src/index.ts` | Updated to use `initSocket()` |
| `backend/api/src/routes/reports.ts` | Broadcast calls after mutations |

### Client Side (Milestone 26)

| File (planned) | Purpose |
|----------------|---------|
| `apps/mobile/lib/shared/services/websocket_service.dart` | Socket.io connection management |
| `apps/mobile/lib/features/feed/providers/feed_providers.dart` | Updated to merge WebSocket events into feed state |
| `apps/mobile/lib/features/map/providers/map_providers.dart` | Updated to add markers from WebSocket events |

### Events

| Event | Direction | Trigger | Room |
|-------|-----------|---------|------|
| `subscribe:location` | Client → Server | App opens / location changes | -- |
| `unsubscribe:location` | Client → Server | App backgrounds | -- |
| `subscribe:report` | Client → Server | User opens a report | -- |
| `unsubscribe:report` | Client → Server | User closes a report | -- |
| `report:new` | Server → Client | New report created | Geo-grid rooms |
| `comment:new` | Server → Client | Comment added | `report:{id}` |
| `report:upvote` | Server → Client | Upvote toggled | `report:{id}` |
| `media:ready` | Server → Client | Media processing done | `report:{id}` |
