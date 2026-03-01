import { createServer } from 'http';
import app from './app';
import { config } from './config';
import { pool } from './lib/db';
import { disconnect as disconnectRedis } from './lib/redis';
import { logger } from './lib/logger';
import { initSocket, shutdownSocket } from './lib/socket';

const httpServer = createServer(app);

initSocket(httpServer);

httpServer.listen(config.port, () => {
  logger.info({ port: config.port, env: config.nodeEnv }, 'CrimeReport API started');
});

function shutdown(signal: string) {
  logger.info({ signal }, 'shutdown signal received');

  shutdownSocket()
    .catch((err) => logger.error({ err }, 'error closing socket.io'))
    .finally(() => {
      logger.info('socket.io closed');

      httpServer.close(async () => {
        logger.info('http server closed');
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

export { app, httpServer };
