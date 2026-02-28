import { Pool, QueryResult, QueryResultRow } from 'pg';
import { config } from '../config';
import { logger } from './logger';

export const pool = new Pool({
  connectionString: config.database.url,
  max: config.database.poolMax,
  idleTimeoutMillis: config.database.idleTimeoutMs,
  connectionTimeoutMillis: config.database.connectionTimeoutMs,
});

pool.on('error', (err) => {
  logger.error({ err }, 'unexpected idle pg client error');
});

pool.on('connect', () => {
  logger.debug('new pg client connected');
});

export async function query<T extends QueryResultRow = QueryResultRow>(
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

export async function checkHealth(): Promise<boolean> {
  try {
    await pool.query('SELECT 1');
    return true;
  } catch {
    return false;
  }
}
