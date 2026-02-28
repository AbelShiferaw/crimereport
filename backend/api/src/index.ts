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
      logger.info('pg pool closed');
      await disconnectRedis().catch((err) => logger.error({ err }, 'error closing redis'));
      logger.info('redis closed');
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

export { app, io, httpServer };
