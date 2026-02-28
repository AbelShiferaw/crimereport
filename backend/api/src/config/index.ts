import dotenv from 'dotenv';

dotenv.config();

function env(key: string, fallback?: string): string {
  const value = process.env[key] ?? fallback;
  if (value === undefined) {
    throw new Error(`Missing required environment variable: ${key}`);
  }
  return value;
}

function envInt(key: string, fallback?: number): number {
  const raw = process.env[key];
  if (raw !== undefined) return parseInt(raw, 10);
  if (fallback !== undefined) return fallback;
  throw new Error(`Missing required environment variable: ${key}`);
}

export const config = {
  nodeEnv: env('NODE_ENV', 'development'),
  port: envInt('PORT', 3000),
  corsOrigin: env('CORS_ORIGIN', '*'),

  database: {
    url: env('DATABASE_URL', ''),
    poolMax: envInt('DB_POOL_MAX', 20),
    idleTimeoutMs: envInt('DB_IDLE_TIMEOUT_MS', 30_000),
    connectionTimeoutMs: envInt('DB_CONNECTION_TIMEOUT_MS', 5_000),
  },

  redis: {
    host: env('REDIS_HOST', 'localhost'),
    port: envInt('REDIS_PORT', 6379),
  },

  aws: {
    region: env('AWS_REGION', 'us-east-1'),
    s3UploadsBucket: env('S3_UPLOADS_BUCKET', ''),
    s3MediaBucket: env('S3_MEDIA_BUCKET', ''),
    cdnDomain: env('CDN_DOMAIN', ''),
  },

  get isDev() {
    return this.nodeEnv === 'development';
  },
  get isProd() {
    return this.nodeEnv === 'production';
  },
} as const;
