# Milestone 21: Comments Endpoints

## Goal
Implement REST API endpoints for creating, reading, and upvoting comments on reports.

## Dependencies
Requires **Milestone 20** complete (report endpoints working).

## Implementation

### 1. Comment Routes
```javascript
// backend/src/routes/v1/comments.js

const express = require('express');
const commentController = require('../../controllers/commentController');
const { validateDevice } = require('../../middleware/validateDevice');
const { validate } = require('../../middleware/validate');
const { commentSchemas } = require('../../validators/commentSchemas');

const router = express.Router();

router.use(validateDevice);

// GET /api/v1/comments/report/:reportId
router.get('/report/:reportId',
  validate(commentSchemas.reportId, 'params'),
  commentController.getCommentsForReport
);

// POST /api/v1/comments
router.post('/',
  validate(commentSchemas.create, 'body'),
  commentController.createComment
);

// POST /api/v1/comments/:id/upvote
router.post('/:id/upvote',
  validate(commentSchemas.id, 'params'),
  commentController.upvoteComment
);

// DELETE /api/v1/comments/:id
router.delete('/:id',
  validate(commentSchemas.id, 'params'),
  commentController.deleteComment
);

module.exports = router;
```

### 2. Comment Controller
```javascript
// backend/src/controllers/commentController.js

const commentService = require('../services/commentService');
const { NotFoundError } = require('../utils/errors');

async function getCommentsForReport(req, res) {
  const { reportId } = req.params;
  const { limit = 50, offset = 0 } = req.query;
  
  const comments = await commentService.getCommentsForReport(
    reportId,
    req.deviceId,
    parseInt(limit),
    parseInt(offset)
  );
  
  res.json({
    data: comments,
    meta: {
      count: comments.length,
      reportId,
    },
  });
}

async function createComment(req, res) {
  const comment = await commentService.createComment({
    ...req.body,
    device_id: req.deviceId,
  });
  
  res.status(201).json({ data: comment });
}

async function upvoteComment(req, res) {
  const result = await commentService.upvoteComment(req.params.id, req.deviceId);
  
  res.json({
    data: {
      commentId: req.params.id,
      upvotes: result.upvotes,
      userUpvoted: result.userUpvoted,
    },
  });
}

async function deleteComment(req, res) {
  await commentService.deleteComment(req.params.id, req.deviceId);
  res.status(204).send();
}

module.exports = {
  getCommentsForReport,
  createComment,
  upvoteComment,
  deleteComment,
};
```

### 3. Comment Service
```javascript
// backend/src/services/commentService.js

const commentRepository = require('../repositories/commentRepository');
const reportRepository = require('../repositories/reportRepository');
const { NotFoundError, ValidationError, UnauthorizedError } = require('../utils/errors');
const { query } = require('../config/database');

async function getCommentsForReport(reportId, deviceId, limit, offset) {
  // Verify report exists
  const report = await reportRepository.findById(reportId);
  if (!report) {
    throw new NotFoundError('Report not found');
  }
  
  const comments = await commentRepository.findByReportId(reportId, limit, offset);
  
  // Enrich with user upvote status and OP flag
  return Promise.all(
    comments.map(async (comment) => {
      const userUpvoted = await hasUserUpvotedComment(comment.id, deviceId);
      return {
        ...comment,
        isReporter: comment.device_id === report.device_id,
        userUpvoted,
        // Hash device ID for display
        anonymousId: hashDeviceId(comment.device_id),
      };
    })
  );
}

async function createComment(data) {
  // Verify report exists
  const report = await reportRepository.findById(data.report_id);
  if (!report) {
    throw new NotFoundError('Report not found');
  }
  
  // Rate limit comments
  await checkCommentRateLimit(data.device_id);
  
  // Create comment
  const comment = await commentRepository.create(data);
  
  // Update report comment count
  await reportRepository.incrementCommentCount(data.report_id);
  
  // TODO: Trigger real-time broadcast (Milestone 23)
  
  return {
    ...comment,
    isReporter: comment.device_id === report.device_id,
    anonymousId: hashDeviceId(comment.device_id),
  };
}

async function upvoteComment(commentId, deviceId) {
  const comment = await commentRepository.findById(commentId);
  if (!comment) {
    throw new NotFoundError('Comment not found');
  }
  
  // Check if already upvoted
  const existing = await query(
    'SELECT 1 FROM comment_upvotes WHERE comment_id = $1 AND device_id = $2',
    [commentId, deviceId]
  );
  
  if (existing.rows.length > 0) {
    // Remove upvote
    await query(
      'DELETE FROM comment_upvotes WHERE comment_id = $1 AND device_id = $2',
      [commentId, deviceId]
    );
    await query(
      'UPDATE comments SET upvotes = upvotes - 1 WHERE id = $1',
      [commentId]
    );
    const updated = await commentRepository.findById(commentId);
    return { upvotes: updated.upvotes, userUpvoted: false };
  } else {
    // Add upvote
    await query(
      'INSERT INTO comment_upvotes (comment_id, device_id) VALUES ($1, $2)',
      [commentId, deviceId]
    );
    await query(
      'UPDATE comments SET upvotes = upvotes + 1 WHERE id = $1',
      [commentId]
    );
    const updated = await commentRepository.findById(commentId);
    return { upvotes: updated.upvotes, userUpvoted: true };
  }
}

async function deleteComment(commentId, deviceId) {
  const comment = await commentRepository.findById(commentId);
  if (!comment) {
    throw new NotFoundError('Comment not found');
  }
  
  // Only the commenter can delete
  if (comment.device_id !== deviceId) {
    throw new UnauthorizedError('You can only delete your own comments');
  }
  
  await commentRepository.delete(commentId);
  
  // Decrement report comment count
  await query(
    'UPDATE reports SET comment_count = comment_count - 1 WHERE id = $1',
    [comment.report_id]
  );
}

async function checkCommentRateLimit(deviceId) {
  const result = await query(
    `SELECT COUNT(*) FROM comments 
     WHERE device_id = $1 AND created_at > NOW() - INTERVAL '1 hour'`,
    [deviceId]
  );
  
  const MAX_COMMENTS_PER_HOUR = 30;
  if (parseInt(result.rows[0].count) >= MAX_COMMENTS_PER_HOUR) {
    throw new ValidationError('Comment rate limit exceeded');
  }
}

async function hasUserUpvotedComment(commentId, deviceId) {
  const result = await query(
    'SELECT 1 FROM comment_upvotes WHERE comment_id = $1 AND device_id = $2',
    [commentId, deviceId]
  );
  return result.rows.length > 0;
}

function hashDeviceId(deviceId) {
  // Create consistent short hash for display
  const crypto = require('crypto');
  return crypto.createHash('sha256').update(deviceId).digest('hex').substring(0, 8);
}

module.exports = {
  getCommentsForReport,
  createComment,
  upvoteComment,
  deleteComment,
};
```

### 4. Comment Repository
```javascript
// backend/src/repositories/commentRepository.js

const BaseRepository = require('./baseRepository');
const { query } = require('../config/database');

class CommentRepository extends BaseRepository {
  constructor() {
    super('comments');
  }
  
  async findByReportId(reportId, limit = 50, offset = 0) {
    const result = await query(
      `SELECT * FROM comments 
       WHERE report_id = $1 
       ORDER BY upvotes DESC, created_at DESC 
       LIMIT $2 OFFSET $3`,
      [reportId, limit, offset]
    );
    return result.rows;
  }
}

module.exports = new CommentRepository();
```

### 5. Validation Schemas
```javascript
// backend/src/validators/commentSchemas.js

const Joi = require('joi');

const commentSchemas = {
  reportId: Joi.object({
    reportId: Joi.string().uuid().required(),
  }),
  
  id: Joi.object({
    id: Joi.string().uuid().required(),
  }),
  
  create: Joi.object({
    report_id: Joi.string().uuid().required(),
    content: Joi.string().min(1).max(1000).required(),
  }),
};

module.exports = { commentSchemas };
```

### 6. Database Migration Addition
```sql
-- migrations/002_comment_upvotes.sql

CREATE TABLE comment_upvotes (
    comment_id UUID REFERENCES comments(id) ON DELETE CASCADE,
    device_id VARCHAR(64) NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    PRIMARY KEY (comment_id, device_id)
);
```

## API Endpoints Summary

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/v1/comments/report/:reportId` | Get comments for report |
| POST | `/api/v1/comments` | Create comment |
| POST | `/api/v1/comments/:id/upvote` | Toggle upvote |
| DELETE | `/api/v1/comments/:id` | Delete own comment |

## Deliverable Checklist
- [ ] GET `/report/:reportId` returns paginated comments
- [ ] Comments sorted by upvotes, then time
- [ ] POST `/` creates comment, updates report count
- [ ] POST `/:id/upvote` toggles upvote state
- [ ] DELETE `/:id` only allows own comment deletion
- [ ] `isReporter` flag identifies OP comments
- [ ] `anonymousId` provides consistent hash
- [ ] Rate limiting on comments (30/hour)
- [ ] All responses follow consistent format
- [ ] Tested with Postman

## Files (5 total)
1. `backend/src/routes/v1/comments.js` - Create
2. `backend/src/controllers/commentController.js` - Create
3. `backend/src/services/commentService.js` - Create
4. `backend/src/repositories/commentRepository.js` - Create
5. `backend/src/validators/commentSchemas.js` - Create
