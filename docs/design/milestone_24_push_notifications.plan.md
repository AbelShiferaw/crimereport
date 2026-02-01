# Milestone 24: Push Notifications

## Goal
Implement push notifications via AWS SNS and Firebase Cloud Messaging (FCM) for nearby crime alerts.

## Dependencies
Requires **Milestone 20** (report endpoints) and Firebase project setup.

## Implementation

### 1. AWS SNS Setup
```hcl
# infrastructure/sns.tf

resource "aws_sns_platform_application" "ios" {
  name                = "reportcrime-ios"
  platform            = "APNS"  # or APNS_SANDBOX for dev
  platform_credential = var.apns_key
  platform_principal  = var.apns_cert
}

resource "aws_sns_platform_application" "android" {
  name                = "reportcrime-android"
  platform            = "GCM"
  platform_credential = var.fcm_server_key
}
```

### 2. Device Registration Routes
```javascript
// backend/src/routes/v1/notifications.js

const express = require('express');
const notificationController = require('../../controllers/notificationController');
const { validateDevice } = require('../../middleware/validateDevice');
const { validate } = require('../../middleware/validate');
const { notificationSchemas } = require('../../validators/notificationSchemas');

const router = express.Router();

router.use(validateDevice);

// POST /api/v1/notifications/register
router.post('/register',
  validate(notificationSchemas.register, 'body'),
  notificationController.registerDevice
);

// DELETE /api/v1/notifications/unregister
router.delete('/unregister',
  notificationController.unregisterDevice
);

// PUT /api/v1/notifications/preferences
router.put('/preferences',
  validate(notificationSchemas.preferences, 'body'),
  notificationController.updatePreferences
);

module.exports = router;
```

### 3. Notification Controller
```javascript
// backend/src/controllers/notificationController.js

const notificationService = require('../services/notificationService');

async function registerDevice(req, res) {
  const { fcmToken, platform, latitude, longitude } = req.body;
  
  await notificationService.registerDevice({
    deviceId: req.deviceId,
    fcmToken,
    platform,
    latitude,
    longitude,
  });
  
  res.json({ data: { message: 'Device registered for notifications' } });
}

async function unregisterDevice(req, res) {
  await notificationService.unregisterDevice(req.deviceId);
  res.json({ data: { message: 'Device unregistered' } });
}

async function updatePreferences(req, res) {
  const { enabled, radius, types } = req.body;
  
  await notificationService.updatePreferences(req.deviceId, {
    enabled,
    radius,
    types,
  });
  
  res.json({ data: { message: 'Preferences updated' } });
}

module.exports = {
  registerDevice,
  unregisterDevice,
  updatePreferences,
};
```

### 4. Notification Service
```javascript
// backend/src/services/notificationService.js

const { SNSClient, CreatePlatformEndpointCommand, PublishCommand, DeleteEndpointCommand } = require('@aws-sdk/client-sns');
const config = require('../config');
const { query } = require('../config/database');
const logger = require('../utils/logger');

const snsClient = new SNSClient({ region: config.aws.region });

async function registerDevice({ deviceId, fcmToken, platform, latitude, longitude }) {
  // Create SNS platform endpoint
  const platformArn = platform === 'ios'
    ? config.aws.sns.iosArn
    : config.aws.sns.androidArn;
  
  const command = new CreatePlatformEndpointCommand({
    PlatformApplicationArn: platformArn,
    Token: fcmToken,
    CustomUserData: deviceId,
  });
  
  const result = await snsClient.send(command);
  const endpointArn = result.EndpointArn;
  
  // Store in database
  await query(
    `INSERT INTO device_notifications (device_id, fcm_token, platform, endpoint_arn, latitude, longitude)
     VALUES ($1, $2, $3, $4, $5, $6)
     ON CONFLICT (device_id) DO UPDATE SET
       fcm_token = $2,
       endpoint_arn = $4,
       latitude = $5,
       longitude = $6,
       updated_at = NOW()`,
    [deviceId, fcmToken, platform, endpointArn, latitude, longitude]
  );
  
  logger.info(`Registered device ${deviceId.substring(0, 8)} for notifications`);
}

async function unregisterDevice(deviceId) {
  const result = await query(
    'SELECT endpoint_arn FROM device_notifications WHERE device_id = $1',
    [deviceId]
  );
  
  if (result.rows[0]?.endpoint_arn) {
    await snsClient.send(new DeleteEndpointCommand({
      EndpointArn: result.rows[0].endpoint_arn,
    }));
  }
  
  await query('DELETE FROM device_notifications WHERE device_id = $1', [deviceId]);
}

async function updatePreferences(deviceId, { enabled, radius, types }) {
  await query(
    `UPDATE device_notifications SET
       enabled = COALESCE($2, enabled),
       radius = COALESCE($3, radius),
       types = COALESCE($4, types),
       updated_at = NOW()
     WHERE device_id = $1`,
    [deviceId, enabled, radius, types ? JSON.stringify(types) : null]
  );
}

async function sendNearbyReportNotification(report) {
  // Find devices near this report
  const devices = await query(
    `SELECT dn.* FROM device_notifications dn
     WHERE dn.enabled = true
       AND ST_DWithin(
         ST_SetSRID(ST_MakePoint(dn.longitude, dn.latitude), 4326)::geography,
         ST_SetSRID(ST_MakePoint($1, $2), 4326)::geography,
         dn.radius
       )
       AND (dn.types IS NULL OR dn.types @> $3)
       AND dn.device_id != $4`,
    [report.longitude, report.latitude, JSON.stringify([report.type]), report.device_id]
  );
  
  logger.info(`Sending notification to ${devices.rows.length} devices for report ${report.id}`);
  
  const notification = {
    title: `${report.type.charAt(0).toUpperCase() + report.type.slice(1)} Reported Nearby`,
    body: report.description?.substring(0, 100) || 'A new crime was reported in your area',
    data: {
      reportId: report.id,
      type: 'NEW_REPORT',
      latitude: String(report.latitude),
      longitude: String(report.longitude),
    },
  };
  
  // Send to all matching devices
  const sendPromises = devices.rows.map(device =>
    sendPushNotification(device.endpoint_arn, notification, device.platform)
  );
  
  await Promise.allSettled(sendPromises);
}

async function sendPushNotification(endpointArn, notification, platform) {
  try {
    const message = platform === 'ios'
      ? {
          APNS: JSON.stringify({
            aps: {
              alert: { title: notification.title, body: notification.body },
              sound: 'default',
              badge: 1,
            },
            data: notification.data,
          }),
        }
      : {
          GCM: JSON.stringify({
            notification: {
              title: notification.title,
              body: notification.body,
            },
            data: notification.data,
          }),
        };
    
    await snsClient.send(new PublishCommand({
      TargetArn: endpointArn,
      Message: JSON.stringify(message),
      MessageStructure: 'json',
    }));
  } catch (error) {
    logger.error(`Failed to send push notification: ${error.message}`);
    
    // Handle invalid endpoint (user uninstalled app)
    if (error.code === 'EndpointDisabled') {
      await query(
        'UPDATE device_notifications SET enabled = false WHERE endpoint_arn = $1',
        [endpointArn]
      );
    }
  }
}

module.exports = {
  registerDevice,
  unregisterDevice,
  updatePreferences,
  sendNearbyReportNotification,
};
```

### 5. Database Migration
```sql
-- migrations/003_notifications.sql

CREATE TABLE device_notifications (
    device_id VARCHAR(64) PRIMARY KEY,
    fcm_token VARCHAR(500) NOT NULL,
    platform VARCHAR(10) NOT NULL,  -- 'ios' or 'android'
    endpoint_arn VARCHAR(500),
    latitude DOUBLE PRECISION,
    longitude DOUBLE PRECISION,
    radius INTEGER DEFAULT 10000,   -- meters
    types JSONB,                    -- crime types to notify
    enabled BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_device_notifications_location ON device_notifications
  USING GIST (ST_SetSRID(ST_MakePoint(longitude, latitude), 4326)::geography);
```

### 6. Validation Schemas
```javascript
// backend/src/validators/notificationSchemas.js

const Joi = require('joi');

const notificationSchemas = {
  register: Joi.object({
    fcmToken: Joi.string().required(),
    platform: Joi.string().valid('ios', 'android').required(),
    latitude: Joi.number().min(-90).max(90).required(),
    longitude: Joi.number().min(-180).max(180).required(),
  }),
  
  preferences: Joi.object({
    enabled: Joi.boolean(),
    radius: Joi.number().min(1000).max(50000),
    types: Joi.array().items(
      Joi.string().valid(
        'theft', 'assault', 'vandalism', 'suspicious',
        'drugActivity', 'disturbance', 'other'
      )
    ),
  }),
};

module.exports = { notificationSchemas };
```

### 7. Integration with Report Service
```javascript
// backend/src/services/reportService.js (addition)

const { sendNearbyReportNotification } = require('./notificationService');

async function createReport(data) {
  // ... existing code ...
  
  const report = await reportRepository.createWithLocation(data);
  const enrichedReport = await getReportById(report.id);
  
  // Send push notifications asynchronously
  sendNearbyReportNotification(enrichedReport).catch(err => {
    logger.error('Failed to send notifications:', err);
  });
  
  return report;
}
```

## API Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/api/v1/notifications/register` | Register device for push |
| DELETE | `/api/v1/notifications/unregister` | Unregister device |
| PUT | `/api/v1/notifications/preferences` | Update notification prefs |

## Deliverable Checklist
- [ ] SNS platform applications created (iOS, Android)
- [ ] POST `/register` creates SNS endpoint
- [ ] Device token stored in database
- [ ] Location stored for geo-filtering
- [ ] DELETE `/unregister` removes endpoint
- [ ] PUT `/preferences` updates radius/types
- [ ] New report triggers notifications
- [ ] Only nearby devices receive notification
- [ ] User's own reports don't notify them
- [ ] Invalid endpoints auto-disabled
- [ ] Notifications received on device

## Files (6 total)
1. `infrastructure/sns.tf` - SNS setup
2. `backend/src/routes/v1/notifications.js` - Create
3. `backend/src/controllers/notificationController.js` - Create
4. `backend/src/services/notificationService.js` - Create
5. `backend/src/validators/notificationSchemas.js` - Create
6. `migrations/003_notifications.sql` - Database table
