import { Pool, PoolConfig, QueryResult, QueryResultRow } from 'pg';
import { config } from '../config';
import { logger } from './logger';

function buildPoolConfig(): PoolConfig {
  const base: PoolConfig = {
    max: config.database.poolMax,
    idleTimeoutMillis: config.database.idleTimeoutMs,
    connectionTimeoutMillis: config.database.connectionTimeoutMs,
  };

  const raw = config.database.url;
  if (!raw) return base;

  // Secrets Manager injects a JSON object; a normal URL starts with postgres://
  if (raw.startsWith('{')) {
    try {
      const secret = JSON.parse(raw) as {
        username: string;
        password: string;
        host: string;
        port: number;
        dbname?: string;
        dbClusterIdentifier?: string;
      };
      const dbName = secret.dbname || secret.dbClusterIdentifier || 'postgres';
      return {
        ...base,
        host: secret.host,
        port: secret.port,
        user: secret.username,
        password: secret.password,
        database: dbName,
        ssl: { rejectUnauthorized: false },
      };
    } catch {
      logger.warn('DATABASE_URL looks like JSON but failed to parse, treating as connection string');
    }
  }

  return { ...base, connectionString: raw };
}

export const pool = new Pool(buildPoolConfig());

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
