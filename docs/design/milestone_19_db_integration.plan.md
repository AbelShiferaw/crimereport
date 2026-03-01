# Milestone 19: Database Integration

## Status
Completed

## Goal
Connect the API server to PostgreSQL (with PostGIS) and Redis, implement connection pooling, query helpers, health checks, SQL migrations, and shared TypeScript type definitions.

## Dependencies
Requires **Milestone 15** (databases running) and **Milestone 18** (API foundation).

## What Was Built
A PostgreSQL connection pool (`pg.Pool`) with support for both standard connection strings and AWS Secrets Manager JSON payloads. A Redis client using the official `redis` package with lazy connect, reconnect strategy, and a health check with timeout. Three SQL migration files managed by `node-pg-migrate`. A pre-boot migration runner script (`scripts/migrate.js`) that parses `DATABASE_URL` and runs migrations before the server starts. A comprehensive `models/types.ts` defining all shared TypeScript interfaces.

## Key Files

| File | Description |
|------|-------------|
| `backend/api/src/lib/db.ts` | PostgreSQL pool, generic `query<T>()` helper, `getClient()`, `checkHealth()` |
| `backend/api/src/lib/redis.ts` | Redis client with lazy connect, reconnect strategy, `checkHealth()`, `disconnect()` |
| `backend/api/src/models/types.ts` | Shared TypeScript interfaces for all domain entities |
| `backend/api/migrations/1709000000000_initial-schema.sql` | Creates reports, media, comments, report_upvotes, device_activity tables + PostGIS indexes |
| `backend/api/migrations/1709100000000_add-comment-flags.sql` | Adds `flag_count` to comments, creates `comment_flags` table |
| `backend/api/migrations/1709200000000_add-media-key.sql` | Adds `media_key` and `status` columns to media table |
| `backend/api/scripts/migrate.js` | Pre-boot migration runner (supports Secrets Manager JSON) |
| `backend/api/package.json` | `node-pg-migrate` dependency + `migrate:up`/`migrate:down` scripts |

## Implementation Details

### 1. PostgreSQL Connection Pool

The pool supports both `postgres://` connection strings and AWS Secrets Manager JSON payloads:

```typescript
// backend/api/src/lib/db.ts
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

  if (raw.startsWith('{')) {
    try {
      const secret = JSON.parse(raw) as {
        username: string; password: string;
        host: string; port: number;
        dbname?: string; dbClusterIdentifier?: string;
      };
      const dbName = secret.dbname || secret.dbClusterIdentifier || 'postgres';
      return {
        ...base,
        host: secret.host, port: secret.port,
        user: secret.username, password: secret.password,
        database: dbName, ssl: { rejectUnauthorized: false },
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
```

### 2. Generic Query Helper

A typed query wrapper that logs duration and row count:

```typescript
// backend/api/src/lib/db.ts (continued)
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
```

### 3. Redis Client

Uses the official `redis` package (v4) with lazy connection and a health check that times out after 3 seconds:

```typescript
// backend/api/src/lib/redis.ts
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

  client.on('error', (err) => { logger.error({ err }, 'redis client error'); });
  client.on('reconnecting', () => { logger.warn('redis reconnecting'); });
  client.on('ready', () => { logger.info('redis connected'); });

  await client.connect();
  return client;
}

export async function checkHealth(): Promise<boolean> {
  try {
    const result = await Promise.race([
      getClient().then((c) => c.ping()),
      new Promise<never>((_, reject) =>
        setTimeout(() => reject(new Error('redis health check timeout')), 3_000),
      ),
    ]);
    return result === 'PONG';
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
```

### 4. TypeScript Type Definitions

All domain entities are defined as interfaces in a shared types file:

```typescript
// backend/api/src/models/types.ts
export interface Coordinates { lat: number; lng: number; }

export interface ReportRow {
  id: string;
  device_id: string;
  type: string;
  description: string | null;
  lat: number;
  lng: number;
  address: string | null;
  status: string;
  upvotes: number;
  comment_count: number;
  created_at: Date;
  updated_at: Date;
  distance_m?: number;
}

export interface CreateReportInput {
  device_id: string;
  type: string;
  description?: string;
  lat: number;
  lng: number;
  address?: string;
}

export interface Media {
  id: string;
  report_id: string;
  type: 'video' | 'image';
  url: string;
  thumbnail_url: string | null;
  media_key: string | null;
  status: string;
  duration_ms: number | null;
  width: number | null;
  height: number | null;
  created_at: Date;
}

export interface Comment {
  id: string;
  report_id: string;
  device_id: string;
  content: string;
  upvotes: number;
  flag_count: number;
  created_at: Date;
}

export interface ReportUpvote {
  report_id: string;
  device_id: string;
  created_at: Date;
}

export interface DeviceActivity {
  device_id: string;
  report_count_today: number;
  last_report_at: Date | null;
  flagged: boolean;
  created_at: Date;
}

export interface PaginationOptions { limit: number; offset: number; }
```

### 5. Database Migrations

Managed by `node-pg-migrate`. Three migration files exist:

**Initial schema** (`1709000000000_initial-schema.sql`):
```sql
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE TABLE reports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    device_id VARCHAR(64) NOT NULL,
    type VARCHAR(50) NOT NULL,
    description TEXT,
    location GEOGRAPHY(POINT, 4326) NOT NULL,
    address VARCHAR(255),
    status VARCHAR(20) NOT NULL DEFAULT 'pending',
    upvotes INTEGER NOT NULL DEFAULT 0,
    comment_count INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_reports_location ON reports USING GIST(location);
CREATE INDEX idx_reports_created_at ON reports(created_at DESC);
CREATE INDEX idx_reports_device_id ON reports(device_id);
CREATE INDEX idx_reports_type ON reports(type);
CREATE INDEX idx_reports_status ON reports(status);

CREATE TABLE media (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    report_id UUID NOT NULL REFERENCES reports(id) ON DELETE CASCADE,
    type VARCHAR(10) NOT NULL CHECK (type IN ('video', 'image')),
    url VARCHAR(500) NOT NULL,
    thumbnail_url VARCHAR(500),
    duration_ms INTEGER,
    width INTEGER,
    height INTEGER,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE comments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    report_id UUID NOT NULL REFERENCES reports(id) ON DELETE CASCADE,
    device_id VARCHAR(64) NOT NULL,
    content TEXT NOT NULL,
    upvotes INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE report_upvotes (
    report_id UUID NOT NULL REFERENCES reports(id) ON DELETE CASCADE,
    device_id VARCHAR(64) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (report_id, device_id)
);

CREATE TABLE device_activity (
    device_id VARCHAR(64) PRIMARY KEY,
    report_count_today INTEGER NOT NULL DEFAULT 0,
    last_report_at TIMESTAMPTZ,
    flagged BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Auto-update updated_at on reports
CREATE OR REPLACE FUNCTION update_updated_at() RETURNS TRIGGER AS $$
BEGIN NEW.updated_at = NOW(); RETURN NEW; END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_reports_updated_at
    BEFORE UPDATE ON reports FOR EACH ROW EXECUTE FUNCTION update_updated_at();
```

**Comment flags** (`1709100000000_add-comment-flags.sql`):
```sql
ALTER TABLE comments ADD COLUMN flag_count INTEGER NOT NULL DEFAULT 0;

CREATE TABLE comment_flags (
    comment_id UUID NOT NULL REFERENCES comments(id) ON DELETE CASCADE,
    device_id VARCHAR(64) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (comment_id, device_id)
);
```

**Media key** (`1709200000000_add-media-key.sql`):
```sql
ALTER TABLE media ADD COLUMN media_key VARCHAR(500);
ALTER TABLE media ADD COLUMN status VARCHAR(20) NOT NULL DEFAULT 'pending';
CREATE INDEX idx_media_media_key ON media(media_key);
CREATE INDEX idx_media_status ON media(status);
```

### 6. Migration Runner Script

Runs as a pre-boot step in the Docker CMD. Supports both standard `postgres://` URLs and AWS Secrets Manager JSON:

```javascript
// backend/api/scripts/migrate.js
const { execSync } = require('child_process');

function buildDatabaseUrl() {
  const raw = process.env.DATABASE_URL || '';
  if (!raw) throw new Error('DATABASE_URL is not set');

  if (raw.startsWith('{')) {
    const secret = JSON.parse(raw);
    const db = secret.dbname || secret.dbClusterIdentifier || 'postgres';
    const pw = encodeURIComponent(secret.password);
    return `postgresql://${secret.username}:${pw}@${secret.host}:${secret.port}/${db}?sslmode=no-verify`;
  }

  return raw;
}

const url = buildDatabaseUrl();
execSync(`npx node-pg-migrate up --database-url-var MIGRATE_DB_URL -m migrations`, {
  stdio: 'inherit',
  env: { ...process.env, MIGRATE_DB_URL: url },
});
```

## Testing

No dedicated unit tests for `db.ts` or `redis.ts` modules themselves, but the health endpoint test (`backend/api/src/__tests__/routes/health.test.ts`) mocks both `checkHealth` functions to verify the `/health/ready` endpoint behavior.

## Notes

**Deviations from original plan:**
- **No repository pattern.** The original plan had `BaseRepository` and `ReportRepository` classes. Instead, each entity uses a plain module of exported async functions (e.g., `models/report.ts`). This is lighter-weight and more idiomatic for the codebase.
- **No cache layer.** The original plan had `reportCacheService.js` with Redis caching for nearby queries. This was not implemented — the app queries PostgreSQL directly. Caching can be added later if needed.
- **`redis` package** (v4, official Node.js client) replaced `ioredis` from the original plan.
- **Secrets Manager JSON support** was added to both `db.ts` and `scripts/migrate.js` for seamless ECS deployment where `DATABASE_URL` is injected as a JSON secret.
- **`node-pg-migrate`** is used with raw `.sql` migration files rather than programmatic JS migrations.
- **All files are TypeScript** — the original plan used `.js` with `require()`.
- **Config for DB/Redis** lives in the central `config/index.ts` (not separate `database.js`/`redis.js` config files).
