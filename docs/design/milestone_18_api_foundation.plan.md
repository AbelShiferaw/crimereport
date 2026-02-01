# Milestone 18: API Server Foundation

## Goal
Build the Node.js/Express API server foundation with proper project structure, middleware, and error handling.

## Dependencies
Requires **Milestone 17** complete (ECS Fargate running placeholder).

## Implementation

### 1. Project Structure
```
backend/
├── src/
│   ├── index.js              # Entry point
│   ├── app.js                # Express app setup
│   ├── config/
│   │   ├── index.js          # Environment config
│   │   └── database.js       # DB connection
│   ├── middleware/
│   │   ├── errorHandler.js   # Global error handler
│   │   ├── requestLogger.js  # Request logging
│   │   ├── rateLimit.js      # Rate limiting
│   │   └── validateDevice.js # Device ID validation
│   ├── routes/
│   │   ├── index.js          # Route aggregator
│   │   ├── health.js         # Health checks
│   │   └── v1/               # API v1 routes
│   ├── services/             # Business logic
│   ├── models/               # Database models
│   └── utils/
│       ├── logger.js         # Winston logger
│       └── errors.js         # Custom error classes
├── Dockerfile
├── package.json
└── .env.example
```

### 2. Express App Setup
```javascript
// backend/src/app.js

const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const compression = require('compression');

const { requestLogger } = require('./middleware/requestLogger');
const { errorHandler } = require('./middleware/errorHandler');
const { rateLimit } = require('./middleware/rateLimit');
const routes = require('./routes');

const app = express();

// Security middleware
app.use(helmet());
app.use(cors({
  origin: process.env.CORS_ORIGINS?.split(',') || '*',
  credentials: true,
}));

// Request parsing
app.use(express.json({ limit: '10mb' }));
app.use(compression());

// Logging
app.use(requestLogger);

// Rate limiting
app.use(rateLimit);

// Routes
app.use(routes);

// Error handling (must be last)
app.use(errorHandler);

module.exports = app;
```

### 3. Entry Point
```javascript
// backend/src/index.js

require('dotenv').config();
const http = require('http');
const app = require('./app');
const { initDatabase } = require('./config/database');
const { initRedis } = require('./config/redis');
const logger = require('./utils/logger');

const PORT = process.env.PORT || 3000;

async function start() {
  try {
    // Initialize connections
    await initDatabase();
    await initRedis();
    
    // Create HTTP server (for WebSocket later)
    const server = http.createServer(app);
    
    server.listen(PORT, () => {
      logger.info(`Server running on port ${PORT}`);
    });
    
    // Graceful shutdown
    process.on('SIGTERM', async () => {
      logger.info('SIGTERM received, shutting down...');
      server.close(() => {
        logger.info('Server closed');
        process.exit(0);
      });
    });
    
  } catch (error) {
    logger.error('Failed to start server:', error);
    process.exit(1);
  }
}

start();
```

### 4. Configuration
```javascript
// backend/src/config/index.js

module.exports = {
  env: process.env.NODE_ENV || 'development',
  port: parseInt(process.env.PORT, 10) || 3000,
  
  database: {
    url: process.env.DATABASE_URL,
    pool: {
      min: 2,
      max: 10,
    },
  },
  
  redis: {
    url: process.env.REDIS_URL,
  },
  
  aws: {
    region: process.env.AWS_REGION || 'us-east-1',
    s3: {
      uploadsBucket: process.env.S3_UPLOADS_BUCKET,
      mediaBucket: process.env.S3_MEDIA_BUCKET,
    },
    cdnDomain: process.env.CDN_DOMAIN,
  },
  
  rateLimit: {
    windowMs: 60 * 1000, // 1 minute
    max: 100, // requests per window
  },
};
```

### 5. Error Handler
```javascript
// backend/src/middleware/errorHandler.js

const logger = require('../utils/logger');
const { AppError } = require('../utils/errors');

function errorHandler(err, req, res, next) {
  // Log error
  logger.error({
    message: err.message,
    stack: err.stack,
    path: req.path,
    method: req.method,
    deviceId: req.deviceId,
  });
  
  // Handle known errors
  if (err instanceof AppError) {
    return res.status(err.statusCode).json({
      error: {
        code: err.code,
        message: err.message,
      },
    });
  }
  
  // Handle validation errors
  if (err.name === 'ValidationError') {
    return res.status(400).json({
      error: {
        code: 'VALIDATION_ERROR',
        message: err.message,
      },
    });
  }
  
  // Unknown errors (don't leak details)
  res.status(500).json({
    error: {
      code: 'INTERNAL_ERROR',
      message: 'An unexpected error occurred',
    },
  });
}

module.exports = { errorHandler };
```

### 6. Custom Errors
```javascript
// backend/src/utils/errors.js

class AppError extends Error {
  constructor(message, statusCode = 500, code = 'INTERNAL_ERROR') {
    super(message);
    this.statusCode = statusCode;
    this.code = code;
    Error.captureStackTrace(this, this.constructor);
  }
}

class NotFoundError extends AppError {
  constructor(message = 'Resource not found') {
    super(message, 404, 'NOT_FOUND');
  }
}

class ValidationError extends AppError {
  constructor(message = 'Validation failed') {
    super(message, 400, 'VALIDATION_ERROR');
  }
}

class UnauthorizedError extends AppError {
  constructor(message = 'Unauthorized') {
    super(message, 401, 'UNAUTHORIZED');
  }
}

class RateLimitError extends AppError {
  constructor(message = 'Too many requests') {
    super(message, 429, 'RATE_LIMIT_EXCEEDED');
  }
}

module.exports = {
  AppError,
  NotFoundError,
  ValidationError,
  UnauthorizedError,
  RateLimitError,
};
```

### 7. Logger
```javascript
// backend/src/utils/logger.js

const winston = require('winston');
const config = require('../config');

const logger = winston.createLogger({
  level: config.env === 'production' ? 'info' : 'debug',
  format: winston.format.combine(
    winston.format.timestamp(),
    winston.format.errors({ stack: true }),
    winston.format.json(),
  ),
  defaultMeta: { service: 'reportcrime-api' },
  transports: [
    new winston.transports.Console({
      format: config.env === 'production'
        ? winston.format.json()
        : winston.format.combine(
            winston.format.colorize(),
            winston.format.simple(),
          ),
    }),
  ],
});

module.exports = logger;
```

### 8. Health Routes
```javascript
// backend/src/routes/health.js

const express = require('express');
const { pool } = require('../config/database');
const { redis } = require('../config/redis');

const router = express.Router();

// Basic health check
router.get('/health', (req, res) => {
  res.json({ status: 'healthy', timestamp: new Date().toISOString() });
});

// Detailed health check
router.get('/health/ready', async (req, res) => {
  const checks = {
    database: false,
    redis: false,
  };
  
  try {
    await pool.query('SELECT 1');
    checks.database = true;
  } catch (e) { /* ignore */ }
  
  try {
    await redis.ping();
    checks.redis = true;
  } catch (e) { /* ignore */ }
  
  const healthy = Object.values(checks).every(Boolean);
  
  res.status(healthy ? 200 : 503).json({
    status: healthy ? 'ready' : 'degraded',
    checks,
    timestamp: new Date().toISOString(),
  });
});

module.exports = router;
```

## Deliverable Checklist
- [ ] Project structure created
- [ ] Express app with middleware chain
- [ ] Environment configuration working
- [ ] Winston logger outputting JSON
- [ ] Custom error classes defined
- [ ] Global error handler catches all errors
- [ ] `/health` returns 200
- [ ] `/health/ready` checks DB and Redis
- [ ] Rate limiting middleware active
- [ ] CORS configured properly
- [ ] Graceful shutdown implemented

## Files (12 total)
1. `backend/src/index.js`
2. `backend/src/app.js`
3. `backend/src/config/index.js`
4. `backend/src/config/database.js`
5. `backend/src/config/redis.js`
6. `backend/src/middleware/errorHandler.js`
7. `backend/src/middleware/requestLogger.js`
8. `backend/src/middleware/rateLimit.js`
9. `backend/src/utils/logger.js`
10. `backend/src/utils/errors.js`
11. `backend/src/routes/index.js`
12. `backend/src/routes/health.js`
