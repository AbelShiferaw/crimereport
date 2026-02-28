import { createClient, RedisClientType } from 'redis';
import { config } from '../config';
import { logger } from './logger';

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

  client.on('error', (err) => {
    logger.error({ err }, 'redis client error');
  });

  client.on('reconnecting', () => {
    logger.warn('redis reconnecting');
  });

  client.on('ready', () => {
    logger.info('redis connected');
  });

  await client.connect();
  return client;
}

export async function checkHealth(): Promise<boolean> {
  try {
    const c = await getClient();
    const pong = await c.ping();
    return pong === 'PONG';
  } catch {
    return false;
  }
}

export async function disconnect(): Promise<void> {
  if (client && client.isOpen) {
    await client.quit();
    client = null;
  }
}
