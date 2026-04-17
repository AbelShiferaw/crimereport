import { Server as SocketServer, Socket } from 'socket.io';
import { createAdapter } from '@socket.io/redis-adapter';
import { createClient } from 'redis';
import { config } from '../config';
import { logger } from './logger';
import * as metrics from './metrics';

let io: SocketServer | null = null;
let redisAdapterHealthy = false;

const GRID_SIZE = 0.1; // ~11 km at the equator
const MAX_REPORT_ROOMS = 50;
const MAX_CONNECTIONS_PER_DEVICE = 3;
const REDIS_RETRY_ATTEMPTS = 3;
const REDIS_RETRY_DELAY_MS = 2000;

const deviceConnectionCount = new Map<string, number>();
const WS_METRICS_INTERVAL_MS = 60_000;
let wsMetricsTimer: ReturnType<typeof setInterval> | null = null;

function emitConnectionGauge(): void {
  if (!io) return;
  const count = io.engine?.clientsCount ?? 0;
  metrics.recordWebSocketConnections(count).catch((err) =>
    logger.warn({ err }, 'failed to record WebSocketConnections metric'),
  );
}

export function getIO(): SocketServer {
  if (!io) throw new Error('Socket.io not initialised');
  return io;
}

export function isRedisAdapterHealthy(): boolean {
  return redisAdapterHealthy;
}

async function connectRedisAdapter(socketServer: SocketServer): Promise<void> {
  for (let attempt = 1; attempt <= REDIS_RETRY_ATTEMPTS; attempt++) {
    try {
      const pubClient = createClient({
        socket: { host: config.redis.host, port: config.redis.port, tls: config.isProd },
      });
      const subClient = pubClient.duplicate();

      pubClient.on('error', (err) => {
        logger.error({ err }, 'socket.io redis pub client error');
        redisAdapterHealthy = false;
      });
      subClient.on('error', (err) => {
        logger.error({ err }, 'socket.io redis sub client error');
        redisAdapterHealthy = false;
      });

      await Promise.all([pubClient.connect(), subClient.connect()]);
      socketServer.adapter(createAdapter(pubClient, subClient));
      redisAdapterHealthy = true;
      logger.info('socket.io redis adapter attached');
      return;
    } catch (err) {
      const isLastAttempt = attempt === REDIS_RETRY_ATTEMPTS;
      const level = config.isProd ? 'error' : 'warn';
      logger[level](
        { err, attempt, maxAttempts: REDIS_RETRY_ATTEMPTS },
        `socket.io redis adapter connection attempt ${attempt}/${REDIS_RETRY_ATTEMPTS} failed`,
      );

      if (!isLastAttempt) {
        await new Promise((r) => setTimeout(r, REDIS_RETRY_DELAY_MS));
      }
    }
  }

  redisAdapterHealthy = false;
  if (config.isProd) {
    logger.error('socket.io redis adapter exhausted all retries — broadcasts will NOT propagate across tasks');
  } else {
    logger.warn('socket.io redis adapter unavailable, falling back to in-memory (dev mode)');
  }
}

export function initSocket(httpServer: import('http').Server): SocketServer {
  io = new SocketServer(httpServer, {
    cors: { origin: config.corsOrigin, methods: ['GET', 'POST'] },
    pingTimeout: 60_000,
    pingInterval: 25_000,
  });

  io.use(authMiddleware);
  io.use(connectionLimitMiddleware);
  io.on('connection', handleConnection);

  connectRedisAdapter(io).catch((err) =>
    logger.error({ err }, 'unexpected error in connectRedisAdapter'),
  );

  wsMetricsTimer = setInterval(emitConnectionGauge, WS_METRICS_INTERVAL_MS);
  wsMetricsTimer.unref();

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

function connectionLimitMiddleware(socket: Socket, next: (err?: Error) => void) {
  const deviceId = socket.data.deviceId as string;
  const current = deviceConnectionCount.get(deviceId) ?? 0;
  if (current >= MAX_CONNECTIONS_PER_DEVICE) {
    return next(new Error('Too many concurrent connections for this device'));
  }
  deviceConnectionCount.set(deviceId, current + 1);
  next();
}

function handleConnection(socket: Socket) {
  const deviceId = socket.data.deviceId as string;
  socket.data.reportRooms = new Set<string>();

  logger.info({ socketId: socket.id, deviceId }, 'ws client connected');

  socket.on('subscribe:location', (data: { lat: number; lng: number; radius?: number }) => {
    if (typeof data?.lat !== 'number' || typeof data?.lng !== 'number') return;
    if (data.lat < -90 || data.lat > 90 || data.lng < -180 || data.lng > 180) return;

    if (socket.data.locationRoom) {
      socket.leave(socket.data.locationRoom);
    }

    const room = locationRoom(data.lat, data.lng);
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
    if (typeof reportId !== 'string' || !reportId) return;
    const reportRooms = socket.data.reportRooms as Set<string>;
    if (reportRooms.size >= MAX_REPORT_ROOMS) return;
    const room = `report:${reportId}`;
    socket.join(room);
    reportRooms.add(room);
    logger.debug({ socketId: socket.id, reportId }, 'joined report room');
  });

  socket.on('unsubscribe:report', (reportId: string) => {
    if (typeof reportId !== 'string' || !reportId) return;
    const room = `report:${reportId}`;
    socket.leave(room);
    (socket.data.reportRooms as Set<string>).delete(room);
  });

  socket.on('disconnect', (reason) => {
    const count = deviceConnectionCount.get(deviceId) ?? 1;
    if (count <= 1) {
      deviceConnectionCount.delete(deviceId);
    } else {
      deviceConnectionCount.set(deviceId, count - 1);
    }
    logger.info({ socketId: socket.id, reason }, 'ws client disconnected');
  });
}

export function locationRoom(lat: number, lng: number): string {
  const gridLat = Math.floor(lat / GRID_SIZE) * GRID_SIZE;
  const gridLng = Math.floor(lng / GRID_SIZE) * GRID_SIZE;
  return `location:${gridLat.toFixed(1)}:${gridLng.toFixed(1)}`;
}

export function overlappingRooms(lat: number, lng: number): string[] {
  const rooms = new Set<string>();
  for (let dLat = -1; dLat <= 1; dLat++) {
    for (let dLng = -1; dLng <= 1; dLng++) {
      const gridLat = Math.floor((lat + dLat * GRID_SIZE) / GRID_SIZE) * GRID_SIZE;
      const gridLng = Math.floor((lng + dLng * GRID_SIZE) / GRID_SIZE) * GRID_SIZE;
      rooms.add(`location:${gridLat.toFixed(1)}:${gridLng.toFixed(1)}`);
    }
  }
  return [...rooms];
}

export async function shutdownSocket(): Promise<void> {
  if (wsMetricsTimer) {
    clearInterval(wsMetricsTimer);
    wsMetricsTimer = null;
  }
  if (io) {
    await new Promise<void>((resolve) => io!.close(() => resolve()));
    io = null;
    redisAdapterHealthy = false;
    deviceConnectionCount.clear();
  }
}
