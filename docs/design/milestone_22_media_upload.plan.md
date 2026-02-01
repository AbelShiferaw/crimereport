# Milestone 22: Media Upload Flow

## Goal
Implement presigned URL upload flow for videos/images from mobile app to S3.

## Dependencies
Requires **Milestone 16** (media infrastructure) and **Milestone 20** (report endpoints).

## Implementation

### 1. Upload Routes
```javascript
// backend/src/routes/v1/uploads.js

const express = require('express');
const uploadController = require('../../controllers/uploadController');
const { validateDevice } = require('../../middleware/validateDevice');
const { validate } = require('../../middleware/validate');
const { uploadSchemas } = require('../../validators/uploadSchemas');

const router = express.Router();

router.use(validateDevice);

// POST /api/v1/uploads/presigned-url
router.post('/presigned-url',
  validate(uploadSchemas.presignedUrl, 'body'),
  uploadController.getPresignedUrl
);

// POST /api/v1/uploads/complete
router.post('/complete',
  validate(uploadSchemas.complete, 'body'),
  uploadController.completeUpload
);

module.exports = router;
```

### 2. Upload Controller
```javascript
// backend/src/controllers/uploadController.js

const uploadService = require('../services/uploadService');

async function getPresignedUrl(req, res) {
  const { filename, contentType, fileSize } = req.body;
  
  const result = await uploadService.generatePresignedUrl(
    filename,
    contentType,
    fileSize,
    req.deviceId
  );
  
  res.json({
    data: {
      uploadUrl: result.uploadUrl,
      uploadId: result.uploadId,
      key: result.key,
      expiresIn: result.expiresIn,
    },
  });
}

async function completeUpload(req, res) {
  const { uploadId, reportId } = req.body;
  
  const media = await uploadService.completeUpload(
    uploadId,
    reportId,
    req.deviceId
  );
  
  res.json({ data: media });
}

module.exports = {
  getPresignedUrl,
  completeUpload,
};
```

### 3. Upload Service
```javascript
// backend/src/services/uploadService.js

const { S3Client, PutObjectCommand, HeadObjectCommand } = require('@aws-sdk/client-s3');
const { getSignedUrl } = require('@aws-sdk/s3-request-presigner');
const { v4: uuidv4 } = require('uuid');
const config = require('../config');
const mediaRepository = require('../repositories/mediaRepository');
const { ValidationError, NotFoundError } = require('../utils/errors');
const { query } = require('../config/database');

const s3Client = new S3Client({ region: config.aws.region });

// Store pending uploads
const pendingUploads = new Map(); // In production, use Redis

async function generatePresignedUrl(filename, contentType, fileSize, deviceId) {
  // Validate file type
  const allowedTypes = ['video/mp4', 'video/quicktime', 'image/jpeg', 'image/png'];
  if (!allowedTypes.includes(contentType)) {
    throw new ValidationError(`File type ${contentType} not allowed`);
  }
  
  // Validate file size (100MB max for video, 10MB for image)
  const isVideo = contentType.startsWith('video/');
  const maxSize = isVideo ? 100 * 1024 * 1024 : 10 * 1024 * 1024;
  if (fileSize > maxSize) {
    throw new ValidationError(`File too large. Max: ${maxSize / 1024 / 1024}MB`);
  }
  
  // Generate unique key
  const uploadId = uuidv4();
  const ext = filename.split('.').pop();
  const folder = isVideo ? 'videos' : 'images';
  const key = `${folder}/${uploadId}.${ext}`;
  
  // Generate presigned URL
  const command = new PutObjectCommand({
    Bucket: config.aws.s3.uploadsBucket,
    Key: key,
    ContentType: contentType,
    ContentLength: fileSize,
    Metadata: {
      'device-id': deviceId,
      'upload-id': uploadId,
    },
  });
  
  const uploadUrl = await getSignedUrl(s3Client, command, { expiresIn: 3600 });
  
  // Track pending upload
  pendingUploads.set(uploadId, {
    key,
    deviceId,
    contentType,
    fileSize,
    isVideo,
    createdAt: new Date(),
  });
  
  // Auto-cleanup after 1 hour
  setTimeout(() => pendingUploads.delete(uploadId), 3600 * 1000);
  
  return {
    uploadUrl,
    uploadId,
    key,
    expiresIn: 3600,
  };
}

async function completeUpload(uploadId, reportId, deviceId) {
  // Verify pending upload
  const pending = pendingUploads.get(uploadId);
  if (!pending) {
    throw new NotFoundError('Upload not found or expired');
  }
  
  if (pending.deviceId !== deviceId) {
    throw new ValidationError('Upload does not belong to this device');
  }
  
  // Verify file exists in S3
  try {
    await s3Client.send(new HeadObjectCommand({
      Bucket: config.aws.s3.uploadsBucket,
      Key: pending.key,
    }));
  } catch (error) {
    throw new ValidationError('File not found in storage. Please upload again.');
  }
  
  // For videos, the MediaConvert Lambda will process and create the media record
  // For images, we create the media record directly
  
  if (pending.isVideo) {
    // Video will be processed by MediaConvert
    // Store pending media reference
    const media = await mediaRepository.create({
      report_id: reportId,
      type: 'video',
      url: '', // Will be updated by MediaConvert callback
      thumbnail_url: '',
      status: 'processing',
      original_key: pending.key,
    });
    
    pendingUploads.delete(uploadId);
    
    return {
      ...media,
      status: 'processing',
      message: 'Video is being processed. It will appear shortly.',
    };
  } else {
    // Image - copy directly to media bucket
    const mediaKey = pending.key.replace('images/', 'processed/images/');
    
    // In production, you might want to resize/optimize images here
    const mediaUrl = `https://${config.aws.cdnDomain}/${mediaKey}`;
    
    const media = await mediaRepository.create({
      report_id: reportId,
      type: 'image',
      url: mediaUrl,
      thumbnail_url: mediaUrl,
      status: 'ready',
    });
    
    pendingUploads.delete(uploadId);
    
    return media;
  }
}

// Webhook endpoint for MediaConvert completion
async function handleMediaConvertComplete(event) {
  const { outputKey, thumbnailKey, originalKey, status } = event;
  
  if (status !== 'COMPLETE') {
    // Handle failure
    await query(
      `UPDATE media SET status = 'failed' WHERE original_key = $1`,
      [originalKey]
    );
    return;
  }
  
  const mediaUrl = `https://${config.aws.cdnDomain}/${outputKey}`;
  const thumbnailUrl = `https://${config.aws.cdnDomain}/${thumbnailKey}`;
  
  await query(
    `UPDATE media SET url = $1, thumbnail_url = $2, status = 'ready' WHERE original_key = $3`,
    [mediaUrl, thumbnailUrl, originalKey]
  );
  
  // TODO: Notify connected clients via WebSocket
}

module.exports = {
  generatePresignedUrl,
  completeUpload,
  handleMediaConvertComplete,
};
```

### 4. Validation Schemas
```javascript
// backend/src/validators/uploadSchemas.js

const Joi = require('joi');

const uploadSchemas = {
  presignedUrl: Joi.object({
    filename: Joi.string().max(255).required(),
    contentType: Joi.string().valid(
      'video/mp4', 'video/quicktime',
      'image/jpeg', 'image/png'
    ).required(),
    fileSize: Joi.number().min(1).max(100 * 1024 * 1024).required(),
  }),
  
  complete: Joi.object({
    uploadId: Joi.string().uuid().required(),
    reportId: Joi.string().uuid().required(),
  }),
};

module.exports = { uploadSchemas };
```

### 5. Media Repository
```javascript
// backend/src/repositories/mediaRepository.js

const BaseRepository = require('./baseRepository');
const { query } = require('../config/database');

class MediaRepository extends BaseRepository {
  constructor() {
    super('media');
  }
  
  async findByReportId(reportId) {
    const result = await query(
      `SELECT * FROM media WHERE report_id = $1 AND status = 'ready' ORDER BY created_at`,
      [reportId]
    );
    return result.rows;
  }
  
  async findPendingByOriginalKey(originalKey) {
    const result = await query(
      `SELECT * FROM media WHERE original_key = $1`,
      [originalKey]
    );
    return result.rows[0];
  }
}

module.exports = new MediaRepository();
```

## Upload Flow Diagram
```
Mobile App                  API Server                  S3/MediaConvert
    │                           │                           │
    │  POST /presigned-url      │                           │
    │ ─────────────────────────>│                           │
    │                           │                           │
    │  { uploadUrl, uploadId }  │                           │
    │ <─────────────────────────│                           │
    │                           │                           │
    │  PUT uploadUrl (file)     │                           │
    │ ─────────────────────────────────────────────────────>│
    │                           │                           │
    │  200 OK                   │                           │
    │ <─────────────────────────────────────────────────────│
    │                           │                           │
    │  POST /complete           │                           │
    │ ─────────────────────────>│                           │
    │                           │  (video triggers          │
    │                           │   MediaConvert)           │
    │  { media, status }        │                           │
    │ <─────────────────────────│                           │
```

## Deliverable Checklist
- [ ] POST `/presigned-url` generates valid S3 URL
- [ ] File type validation working
- [ ] File size limits enforced
- [ ] Client can upload directly to S3
- [ ] POST `/complete` verifies upload exists
- [ ] Images get direct CDN URL
- [ ] Videos get "processing" status
- [ ] MediaConvert webhook updates video status
- [ ] CDN URLs work for playback
- [ ] Error handling for failed uploads

## Files (5 total)
1. `backend/src/routes/v1/uploads.js` - Create
2. `backend/src/controllers/uploadController.js` - Create
3. `backend/src/services/uploadService.js` - Create
4. `backend/src/validators/uploadSchemas.js` - Create
5. `backend/src/repositories/mediaRepository.js` - Update
