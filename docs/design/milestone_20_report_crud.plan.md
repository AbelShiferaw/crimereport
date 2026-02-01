# Milestone 20: Report CRUD Endpoints

## Goal
Implement REST API endpoints for creating, reading, and managing crime reports.

## Dependencies
Requires **Milestone 19** complete (database integration working).

## Implementation

### 1. Report Routes
```javascript
// backend/src/routes/v1/reports.js

const express = require('express');
const reportController = require('../../controllers/reportController');
const { validateDevice } = require('../../middleware/validateDevice');
const { validate } = require('../../middleware/validate');
const { reportSchemas } = require('../../validators/reportSchemas');

const router = express.Router();

// All report routes require device ID
router.use(validateDevice);

// GET /api/v1/reports/nearby
router.get('/nearby',
  validate(reportSchemas.nearby, 'query'),
  reportController.getNearbyReports
);

// GET /api/v1/reports/location
router.get('/location',
  validate(reportSchemas.location, 'query'),
  reportController.getReportsAtLocation
);

// GET /api/v1/reports/:id
router.get('/:id',
  validate(reportSchemas.id, 'params'),
  reportController.getReport
);

// POST /api/v1/reports
router.post('/',
  validate(reportSchemas.create, 'body'),
  reportController.createReport
);

// POST /api/v1/reports/:id/upvote
router.post('/:id/upvote',
  validate(reportSchemas.id, 'params'),
  reportController.upvoteReport
);

// POST /api/v1/reports/:id/flag
router.post('/:id/flag',
  validate(reportSchemas.flag, 'body'),
  reportController.flagReport
);

module.exports = router;
```

### 2. Report Controller
```javascript
// backend/src/controllers/reportController.js

const reportService = require('../services/reportService');
const { NotFoundError } = require('../utils/errors');

async function getNearbyReports(req, res) {
  const { lat, lng, radius = 10000, limit = 50 } = req.query;
  
  const reports = await reportService.getNearbyReports(
    parseFloat(lat),
    parseFloat(lng),
    parseInt(radius),
    parseInt(limit),
    req.deviceId
  );
  
  res.json({
    data: reports,
    meta: {
      count: reports.length,
      lat: parseFloat(lat),
      lng: parseFloat(lng),
      radius: parseInt(radius),
    },
  });
}

async function getReportsAtLocation(req, res) {
  const { lat, lng, tolerance = 100 } = req.query;
  
  const reports = await reportService.getReportsAtLocation(
    parseFloat(lat),
    parseFloat(lng),
    parseInt(tolerance)
  );
  
  res.json({
    data: reports,
    meta: { count: reports.length },
  });
}

async function getReport(req, res) {
  const report = await reportService.getReportById(req.params.id);
  
  if (!report) {
    throw new NotFoundError('Report not found');
  }
  
  res.json({ data: report });
}

async function createReport(req, res) {
  const report = await reportService.createReport({
    ...req.body,
    device_id: req.deviceId,
  });
  
  res.status(201).json({ data: report });
}

async function upvoteReport(req, res) {
  const result = await reportService.upvoteReport(req.params.id, req.deviceId);
  
  res.json({
    data: {
      reportId: req.params.id,
      upvotes: result.upvotes,
      userUpvoted: result.userUpvoted,
    },
  });
}

async function flagReport(req, res) {
  await reportService.flagReport(req.params.id, req.deviceId, req.body.reason);
  
  res.json({
    data: { message: 'Report flagged for review' },
  });
}

module.exports = {
  getNearbyReports,
  getReportsAtLocation,
  getReport,
  createReport,
  upvoteReport,
  flagReport,
};
```

### 3. Report Service
```javascript
// backend/src/services/reportService.js

const reportRepository = require('../repositories/reportRepository');
const mediaRepository = require('../repositories/mediaRepository');
const { getNearbyReportsCached, invalidateNearbyCache } = require('./reportCacheService');
const { ValidationError } = require('../utils/errors');
const { query } = require('../config/database');

async function getNearbyReports(lat, lng, radius, limit, deviceId) {
  const { data: reports } = await getNearbyReportsCached(
    lat, lng, radius,
    () => reportRepository.findNearby(lat, lng, radius, limit)
  );
  
  // Enrich with media and user upvote status
  const enriched = await Promise.all(
    reports.map(async (report) => {
      const media = await mediaRepository.findByReportId(report.id);
      const userUpvoted = await hasUserUpvoted(report.id, deviceId);
      
      return {
        ...report,
        media,
        userUpvoted,
        distance_km: report.distance_meters / 1000,
      };
    })
  );
  
  return enriched;
}

async function getReportsAtLocation(lat, lng, tolerance) {
  const reports = await reportRepository.findAtLocation(lat, lng, tolerance);
  
  return Promise.all(
    reports.map(async (report) => {
      const media = await mediaRepository.findByReportId(report.id);
      return { ...report, media };
    })
  );
}

async function getReportById(id) {
  const report = await reportRepository.findById(id);
  if (!report) return null;
  
  const media = await mediaRepository.findByReportId(id);
  return { ...report, media };
}

async function createReport(data) {
  // Validate rate limit
  await checkReportRateLimit(data.device_id);
  
  // Create report
  const report = await reportRepository.createWithLocation(data);
  
  // Invalidate nearby cache
  await invalidateNearbyCache(data.latitude, data.longitude);
  
  // TODO: Trigger real-time broadcast (Milestone 23)
  
  return report;
}

async function upvoteReport(reportId, deviceId) {
  // Check if already upvoted
  const existing = await query(
    'SELECT 1 FROM report_upvotes WHERE report_id = $1 AND device_id = $2',
    [reportId, deviceId]
  );
  
  if (existing.rows.length > 0) {
    // Remove upvote
    await query(
      'DELETE FROM report_upvotes WHERE report_id = $1 AND device_id = $2',
      [reportId, deviceId]
    );
    await query(
      'UPDATE reports SET upvotes = upvotes - 1 WHERE id = $1',
      [reportId]
    );
    const report = await reportRepository.findById(reportId);
    return { upvotes: report.upvotes, userUpvoted: false };
  } else {
    // Add upvote
    await query(
      'INSERT INTO report_upvotes (report_id, device_id) VALUES ($1, $2)',
      [reportId, deviceId]
    );
    const upvotes = await reportRepository.incrementUpvotes(reportId);
    return { upvotes, userUpvoted: true };
  }
}

async function flagReport(reportId, deviceId, reason) {
  await query(
    `INSERT INTO report_flags (report_id, device_id, reason) VALUES ($1, $2, $3)
     ON CONFLICT (report_id, device_id) DO UPDATE SET reason = $3`,
    [reportId, deviceId, reason]
  );
  
  // Check flag threshold
  const flagCount = await query(
    'SELECT COUNT(*) FROM report_flags WHERE report_id = $1',
    [reportId]
  );
  
  if (parseInt(flagCount.rows[0].count) >= 5) {
    await reportRepository.update(reportId, { status: 'flagged' });
  }
}

async function checkReportRateLimit(deviceId) {
  const result = await query(
    `SELECT report_count_today, last_report_at, flagged 
     FROM device_activity WHERE device_id = $1`,
    [deviceId]
  );
  
  if (result.rows[0]?.flagged) {
    throw new ValidationError('Your device has been flagged for suspicious activity');
  }
  
  const MAX_REPORTS_PER_DAY = 10;
  const count = result.rows[0]?.report_count_today || 0;
  
  if (count >= MAX_REPORTS_PER_DAY) {
    throw new ValidationError(`Maximum ${MAX_REPORTS_PER_DAY} reports per day`);
  }
  
  // Update activity
  await query(
    `INSERT INTO device_activity (device_id, report_count_today, last_report_at)
     VALUES ($1, 1, NOW())
     ON CONFLICT (device_id) DO UPDATE SET
       report_count_today = CASE
         WHEN device_activity.last_report_at::date < CURRENT_DATE THEN 1
         ELSE device_activity.report_count_today + 1
       END,
       last_report_at = NOW()`,
    [deviceId]
  );
}

async function hasUserUpvoted(reportId, deviceId) {
  const result = await query(
    'SELECT 1 FROM report_upvotes WHERE report_id = $1 AND device_id = $2',
    [reportId, deviceId]
  );
  return result.rows.length > 0;
}

module.exports = {
  getNearbyReports,
  getReportsAtLocation,
  getReportById,
  createReport,
  upvoteReport,
  flagReport,
};
```

### 4. Validation Schemas
```javascript
// backend/src/validators/reportSchemas.js

const Joi = require('joi');

const reportSchemas = {
  nearby: Joi.object({
    lat: Joi.number().min(-90).max(90).required(),
    lng: Joi.number().min(-180).max(180).required(),
    radius: Joi.number().min(100).max(50000).default(10000),
    limit: Joi.number().min(1).max(100).default(50),
  }),
  
  location: Joi.object({
    lat: Joi.number().min(-90).max(90).required(),
    lng: Joi.number().min(-180).max(180).required(),
    tolerance: Joi.number().min(10).max(1000).default(100),
  }),
  
  id: Joi.object({
    id: Joi.string().uuid().required(),
  }),
  
  create: Joi.object({
    type: Joi.string().valid(
      'theft', 'assault', 'vandalism', 'suspicious',
      'drugActivity', 'disturbance', 'other'
    ).required(),
    description: Joi.string().max(2000).allow(''),
    latitude: Joi.number().min(-90).max(90).required(),
    longitude: Joi.number().min(-180).max(180).required(),
    address: Joi.string().max(255).allow(''),
  }),
  
  flag: Joi.object({
    reason: Joi.string().valid(
      'spam', 'fake', 'inappropriate', 'duplicate', 'other'
    ).required(),
  }),
};

module.exports = { reportSchemas };
```

## API Endpoints Summary

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/v1/reports/nearby` | Get reports within radius |
| GET | `/api/v1/reports/location` | Get reports at exact location |
| GET | `/api/v1/reports/:id` | Get single report |
| POST | `/api/v1/reports` | Create new report |
| POST | `/api/v1/reports/:id/upvote` | Toggle upvote |
| POST | `/api/v1/reports/:id/flag` | Flag report |

## Deliverable Checklist
- [ ] GET `/nearby` returns geo-filtered reports
- [ ] GET `/location` returns location-specific reports
- [ ] GET `/:id` returns single report with media
- [ ] POST `/` creates report with location
- [ ] POST `/:id/upvote` toggles upvote state
- [ ] POST `/:id/flag` flags report
- [ ] Rate limiting per device working
- [ ] Validation errors return 400
- [ ] All responses follow consistent format
- [ ] Tested with Postman/Insomnia

## Files (5 total)
1. `backend/src/routes/v1/reports.js` - Create
2. `backend/src/controllers/reportController.js` - Create
3. `backend/src/services/reportService.js` - Create
4. `backend/src/validators/reportSchemas.js` - Create
5. `backend/src/middleware/validate.js` - Create
