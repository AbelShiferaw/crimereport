#!/usr/bin/env node

/**
 * Pre-boot migration runner.
 * Parses DATABASE_URL (supports both postgres:// strings and AWS Secrets Manager JSON)
 * then delegates to node-pg-migrate CLI.
 */

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
console.log('[migrate] running database migrations...');

try {
  execSync(
    `npx node-pg-migrate up --database-url-var MIGRATE_DB_URL -m migrations`,
    {
      stdio: 'inherit',
      env: { ...process.env, MIGRATE_DB_URL: url },
    },
  );
  console.log('[migrate] migrations complete');
} catch (err) {
  console.error('[migrate] migration failed:', err.message);
  process.exit(1);
}
