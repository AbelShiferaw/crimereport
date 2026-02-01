# Milestone 19: Database Integration

## Goal
Connect the API server to Aurora PostgreSQL and Redis, implement connection pooling and basic queries.

## Dependencies
Requires **Milestone 15** (databases running) and **Milestone 18** (API foundation).

## Implementation

### 1. PostgreSQL Connection
```javascript
// backend/src/config/database.js

const { Pool } = require('pg');
const config = require('./index');
const logger = require('../utils/logger');

let pool;

async function initDatabase() {
  pool = new Pool({
    connectionString: config.database.url,
    min: config.database.pool.min,
    max: config.database.pool.max,
    idleTimeoutMillis: 30000,
    connectionTimeoutMillis: 5000,
  });
  
  // Test connection
  const client = await pool.connect();
  try {
    const result = await client.query('SELECT PostGIS_Version()');
    logger.info(`Connected to PostgreSQL. PostGIS: ${result.rows[0].postgis_version}`);
  } finally {
    client.release();
  }
  
  // Handle errors
  pool.on('error', (err) => {
    logger.error('Unexpected database error:', err);
  });
  
  return pool;
}

async function query(text, params) {
  const start = Date.now();
  const result = await pool.query(text, params);
  const duration = Date.now() - start;
  
  logger.debug({
    message: 'Executed query',
    query: text.substring(0, 100),
    duration,
    rows: result.rowCount,
  });
  
  return result;
}

async function getClient() {
  return pool.connect();
}

module.exports = { initDatabase, query, getClient, pool: () => pool };
```

### 2. Redis Connection
```javascript
// backend/src/config/redis.js

const Redis = require('ioredis');
const config = require('./index');
const logger = require('../utils/logger');

let redis;

async function initRedis() {
  redis = new Redis(config.redis.url, {
    maxRetriesPerRequest: 3,
    retryDelayOnFailover: 100,
    enableReadyCheck: true,
    lazyConnect: true,
  });
  
  redis.on('connect', () => {
    logger.info('Connected to Redis');
  });
  
  redis.on('error', (err) => {
    logger.error('Redis error:', err);
  });
  
  await redis.connect();
  await redis.ping();
  
  return redis;
}

// Cache helpers
async function cacheGet(key) {
  const value = await redis.get(key);
  return value ? JSON.parse(value) : null;
}

async function cacheSet(key, value, ttlSeconds = 300) {
  await redis.setex(key, ttlSeconds, JSON.stringify(value));
}

async function cacheDelete(key) {
  await redis.del(key);
}

// Pub/Sub for real-time
function getSubscriber() {
  return redis.duplicate();
}

module.exports = {
  initRedis,
  redis: () => redis,
  cacheGet,
  cacheSet,
  cacheDelete,
  getSubscriber,
};
```

### 3. Base Repository Pattern
```javascript
// backend/src/repositories/baseRepository.js

const { query, getClient } = require('../config/database');

class BaseRepository {
  constructor(tableName) {
    this.tableName = tableName;
  }
  
  async findById(id) {
    const result = await query(
      `SELECT * FROM ${this.tableName} WHERE id = $1`,
      [id]
    );
    return result.rows[0] || null;
  }
  
  async findAll(options = {}) {
    const { limit = 50, offset = 0, orderBy = 'created_at DESC' } = options;
    const result = await query(
      `SELECT * FROM ${this.tableName} ORDER BY ${orderBy} LIMIT $1 OFFSET $2`,
      [limit, offset]
    );
    return result.rows;
  }
  
  async create(data) {
    const keys = Object.keys(data);
    const values = Object.values(data);
    const placeholders = keys.map((_, i) => `$${i + 1}`).join(', ');
    
    const result = await query(
      `INSERT INTO ${this.tableName} (${keys.join(', ')}) 
       VALUES (${placeholders}) 
       RETURNING *`,
      values
    );
    return result.rows[0];
  }
  
  async update(id, data) {
    const keys = Object.keys(data);
    const values = Object.values(data);
    const setClause = keys.map((key, i) => `${key} = $${i + 2}`).join(', ');
    
    const result = await query(
      `UPDATE ${this.tableName} SET ${setClause}, updated_at = NOW() 
       WHERE id = $1 
       RETURNING *`,
      [id, ...values]
    );
    return result.rows[0];
  }
  
  async delete(id) {
    const result = await query(
      `DELETE FROM ${this.tableName} WHERE id = $1 RETURNING id`,
      [id]
    );
    return result.rowCount > 0;
  }
  
  // Transaction helper
  async withTransaction(callback) {
    const client = await getClient();
    try {
      await client.query('BEGIN');
      const result = await callback(client);
      await client.query('COMMIT');
      return result;
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
  }
}

module.exports = BaseRepository;
```

### 4. Report Repository with Geo Queries
```javascript
// backend/src/repositories/reportRepository.js

const BaseRepository = require('./baseRepository');
const { query } = require('../config/database');

class ReportRepository extends BaseRepository {
  constructor() {
    super('reports');
  }
  
  async findNearby(lat, lng, radiusMeters = 10000, limit = 50) {
    const result = await query(
      `SELECT 
        r.*,
        ST_Distance(
          r.location,
          ST_SetSRID(ST_MakePoint($1, $2), 4326)::geography
        ) as distance_meters
      FROM reports r
      WHERE ST_DWithin(
        r.location,
        ST_SetSRID(ST_MakePoint($1, $2), 4326)::geography,
        $3
      )
      AND r.status != 'removed'
      ORDER BY r.created_at DESC
      LIMIT $4`,
      [lng, lat, radiusMeters, limit]
    );
    return result.rows;
  }
  
  async findAtLocation(lat, lng, toleranceMeters = 100) {
    const result = await query(
      `SELECT r.*
      FROM reports r
      WHERE ST_DWithin(
        r.location,
        ST_SetSRID(ST_MakePoint($1, $2), 4326)::geography,
        $3
      )
      AND r.status != 'removed'
      ORDER BY r.created_at DESC`,
      [lng, lat, toleranceMeters]
    );
    return result.rows;
  }
  
  async createWithLocation(data) {
    const { latitude, longitude, ...rest } = data;
    
    const result = await query(
      `INSERT INTO reports (
        device_id, type, description, location, address, status
      ) VALUES (
        $1, $2, $3, ST_SetSRID(ST_MakePoint($4, $5), 4326)::geography, $6, $7
      ) RETURNING *,
        ST_X(location::geometry) as longitude,
        ST_Y(location::geometry) as latitude`,
      [rest.device_id, rest.type, rest.description, longitude, latitude, rest.address, 'pending']
    );
    return result.rows[0];
  }
  
  async incrementUpvotes(reportId) {
    const result = await query(
      `UPDATE reports SET upvotes = upvotes + 1 WHERE id = $1 RETURNING upvotes`,
      [reportId]
    );
    return result.rows[0]?.upvotes;
  }
  
  async incrementCommentCount(reportId) {
    await query(
      `UPDATE reports SET comment_count = comment_count + 1 WHERE id = $1`,
      [reportId]
    );
  }
}

module.exports = new ReportRepository();
```

### 5. Cache Layer for Reports
```javascript
// backend/src/services/reportCacheService.js

const { cacheGet, cacheSet, cacheDelete } = require('../config/redis');

const CACHE_TTL = 60; // 1 minute for nearby reports
const CACHE_PREFIX = 'reports:';

function getCacheKey(lat, lng, radius) {
  // Round to reduce cache variations
  const roundedLat = Math.round(lat * 100) / 100;
  const roundedLng = Math.round(lng * 100) / 100;
  return `${CACHE_PREFIX}nearby:${roundedLat}:${roundedLng}:${radius}`;
}

async function getNearbyReportsCached(lat, lng, radius, fetchFn) {
  const key = getCacheKey(lat, lng, radius);
  
  // Try cache first
  const cached = await cacheGet(key);
  if (cached) {
    return { data: cached, fromCache: true };
  }
  
  // Fetch from database
  const data = await fetchFn();
  
  // Cache result
  await cacheSet(key, data, CACHE_TTL);
  
  return { data, fromCache: false };
}

async function invalidateNearbyCache(lat, lng) {
  // Invalidate nearby cache entries (simplified)
  // In production, use Redis SCAN or pub/sub
  const key = getCacheKey(lat, lng, 10000);
  await cacheDelete(key);
}

module.exports = {
  getNearbyReportsCached,
  invalidateNearbyCache,
};
```

## Deliverable Checklist
- [ ] PostgreSQL pool connected
- [ ] Redis connected with pub/sub ready
- [ ] PostGIS queries working
- [ ] BaseRepository with CRUD operations
- [ ] ReportRepository with geo queries
- [ ] `findNearby()` returns reports within radius
- [ ] Cache layer for nearby reports
- [ ] Transaction support working
- [ ] Connection pooling efficient
- [ ] Error handling for DB failures

## Files (6 total)
1. `backend/src/config/database.js` - Update
2. `backend/src/config/redis.js` - Update
3. `backend/src/repositories/baseRepository.js` - Create
4. `backend/src/repositories/reportRepository.js` - Create
5. `backend/src/repositories/commentRepository.js` - Create
6. `backend/src/services/reportCacheService.js` - Create
