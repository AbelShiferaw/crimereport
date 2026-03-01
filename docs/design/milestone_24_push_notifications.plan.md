# Milestone 24: Push Notifications

## Status
Not Started

## Goal
Send push notifications via AWS SNS + Firebase Cloud Messaging (FCM) when a new crime report is created near a registered device. Devices can register/unregister and control notification preferences (radius, crime types).

## Dependencies
- **Milestone 20** – Report creation endpoints (already implemented)
- **Milestone 15** – Aurora PostgreSQL for the `push_subscriptions` table
- **Milestone 14** – VPC with NAT gateway (ECS tasks need outbound access to SNS)
- Firebase project configured with FCM credentials

## Plan

### 1. SNS Infrastructure (`infrastructure/aws/lib/notifications/sns-stack.ts`)

Add an SNS stack that creates platform applications for iOS and Android. The FCM server key and APNs credentials are stored in Secrets Manager and passed in as parameters.

```typescript
// infrastructure/aws/lib/notifications/sns-stack.ts

import * as cdk from 'aws-cdk-lib';
import * as sns from 'aws-cdk-lib/aws-sns';
import { Construct } from 'constructs';

interface SnsStackProps extends cdk.StackProps {
  fcmServerKey: string;
  apnsPlatformCredential: string;
  apnsPlatformPrincipal: string;
}

export class SnsStack extends cdk.Stack {
  public readonly androidPlatformArn: string;
  public readonly iosPlatformArn: string;

  constructor(scope: Construct, id: string, props: SnsStackProps) {
    super(scope, id, props);

    const android = new sns.CfnPlatformApplication(this, 'AndroidApp', {
      name: 'crimereport-android',
      platform: 'GCM',
      attributes: { PlatformCredential: props.fcmServerKey },
    });

    const ios = new sns.CfnPlatformApplication(this, 'IosApp', {
      name: 'crimereport-ios',
      platform: 'APNS',
      attributes: {
        PlatformCredential: props.apnsPlatformCredential,
        PlatformPrincipal: props.apnsPlatformPrincipal,
      },
    });

    this.androidPlatformArn = android.ref;
    this.iosPlatformArn = ios.ref;
  }
}
```

### 2. Database Migration

```sql
-- migrations/NNN_push_subscriptions.sql

CREATE TABLE push_subscriptions (
    device_id   VARCHAR(64) PRIMARY KEY,
    fcm_token   VARCHAR(500) NOT NULL,
    platform    VARCHAR(10)  NOT NULL CHECK (platform IN ('ios', 'android')),
    endpoint_arn VARCHAR(500),
    location    geography(Point, 4326),
    radius      INTEGER      NOT NULL DEFAULT 10000,
    types       TEXT[]       DEFAULT NULL,
    enabled     BOOLEAN      NOT NULL DEFAULT true,
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_push_subscriptions_location
  ON push_subscriptions USING GIST (location);
```

Using a `geography` column instead of raw lat/lng keeps it consistent with the `reports` table and lets PostGIS `ST_DWithin` use the spatial index directly.

### 3. Config Additions (`backend/api/src/config/index.ts`)

```typescript
// Add to the existing config.aws block:
aws: {
  region: env('AWS_REGION', 'us-east-1'),
  s3UploadsBucket: env('S3_UPLOADS_BUCKET', ''),
  s3MediaBucket: env('S3_MEDIA_BUCKET', ''),
  cdnDomain: env('CDN_DOMAIN', ''),
  snsAndroidArn: env('SNS_ANDROID_PLATFORM_ARN', ''),
  snsIosArn: env('SNS_IOS_PLATFORM_ARN', ''),
},
```

### 4. Types (`backend/api/src/models/types.ts`)

```typescript
// Add to existing models/types.ts:

export interface PushSubscription {
  device_id: string;
  fcm_token: string;
  platform: 'ios' | 'android';
  endpoint_arn: string | null;
  lat: number;
  lng: number;
  radius: number;
  types: string[] | null;
  enabled: boolean;
  created_at: Date;
  updated_at: Date;
}

export interface CreatePushSubscriptionInput {
  device_id: string;
  fcm_token: string;
  platform: 'ios' | 'android';
  lat: number;
  lng: number;
}

export interface UpdatePushPreferencesInput {
  enabled?: boolean;
  radius?: number;
  types?: string[];
}
```

### 5. Model (`backend/api/src/models/push-subscription.ts`)

Follows the same pattern as `models/report.ts` — named async exports using the shared `query` function.

```typescript
// backend/api/src/models/push-subscription.ts

import { query } from '../lib/db';
import { PushSubscription, CreatePushSubscriptionInput, UpdatePushPreferencesInput } from './types';

export async function findByDeviceId(deviceId: string): Promise<PushSubscription | null> {
  const { rows } = await query<PushSubscription>(
    `SELECT device_id, fcm_token, platform, endpoint_arn,
            ST_Y(location::geometry) AS lat,
            ST_X(location::geometry) AS lng,
            radius, types, enabled, created_at, updated_at
     FROM push_subscriptions WHERE device_id = $1`,
    [deviceId],
  );
  return rows[0] ?? null;
}

export async function upsert(
  input: CreatePushSubscriptionInput,
  endpointArn: string,
): Promise<PushSubscription> {
  const { rows } = await query<PushSubscription>(
    `INSERT INTO push_subscriptions (device_id, fcm_token, platform, endpoint_arn, location)
     VALUES ($1, $2, $3, $4, ST_SetSRID(ST_MakePoint($6, $5), 4326)::geography)
     ON CONFLICT (device_id) DO UPDATE SET
       fcm_token    = EXCLUDED.fcm_token,
       endpoint_arn = EXCLUDED.endpoint_arn,
       location     = EXCLUDED.location,
       updated_at   = NOW()
     RETURNING device_id, fcm_token, platform, endpoint_arn,
               ST_Y(location::geometry) AS lat,
               ST_X(location::geometry) AS lng,
               radius, types, enabled, created_at, updated_at`,
    [input.device_id, input.fcm_token, input.platform, endpointArn, input.lat, input.lng],
  );
  return rows[0];
}

export async function remove(deviceId: string): Promise<string | null> {
  const { rows } = await query<{ endpoint_arn: string | null }>(
    'DELETE FROM push_subscriptions WHERE device_id = $1 RETURNING endpoint_arn',
    [deviceId],
  );
  return rows[0]?.endpoint_arn ?? null;
}

export async function updatePreferences(
  deviceId: string,
  input: UpdatePushPreferencesInput,
): Promise<PushSubscription | null> {
  const { rows } = await query<PushSubscription>(
    `UPDATE push_subscriptions SET
       enabled    = COALESCE($2, enabled),
       radius     = COALESCE($3, radius),
       types      = COALESCE($4, types),
       updated_at = NOW()
     WHERE device_id = $1
     RETURNING device_id, fcm_token, platform, endpoint_arn,
               ST_Y(location::geometry) AS lat,
               ST_X(location::geometry) AS lng,
               radius, types, enabled, created_at, updated_at`,
    [deviceId, input.enabled ?? null, input.radius ?? null, input.types ?? null],
  );
  return rows[0] ?? null;
}

export async function findNearbyEnabled(
  lat: number,
  lng: number,
  type: string,
  excludeDeviceId: string,
): Promise<PushSubscription[]> {
  const { rows } = await query<PushSubscription>(
    `SELECT device_id, fcm_token, platform, endpoint_arn,
            ST_Y(location::geometry) AS lat,
            ST_X(location::geometry) AS lng,
            radius, types, enabled, created_at, updated_at
     FROM push_subscriptions
     WHERE enabled = true
       AND device_id != $4
       AND ST_DWithin(
             location,
             ST_SetSRID(ST_MakePoint($2, $1), 4326)::geography,
             radius
           )
       AND (types IS NULL OR $3 = ANY(types))`,
    [lat, lng, type, excludeDeviceId],
  );
  return rows;
}

export async function disableByEndpointArn(endpointArn: string): Promise<void> {
  await query(
    'UPDATE push_subscriptions SET enabled = false, updated_at = NOW() WHERE endpoint_arn = $1',
    [endpointArn],
  );
}
```

### 6. Validator (`backend/api/src/validators/push-subscription.ts`)

```typescript
// backend/api/src/validators/push-subscription.ts

import { z } from 'zod';
import { CRIME_TYPES } from './report';

export const registerDeviceSchema = z.object({
  device_id: z.string().min(1).max(64),
  fcm_token: z.string().min(1).max(500),
  platform: z.enum(['ios', 'android']),
  lat: z.number().min(-90).max(90),
  lng: z.number().min(-180).max(180),
});

export const unregisterDeviceSchema = z.object({
  device_id: z.string().min(1).max(64),
});

export const updatePreferencesSchema = z.object({
  device_id: z.string().min(1).max(64),
  enabled: z.boolean().optional(),
  radius: z.number().int().min(1_000).max(50_000).optional(),
  types: z.array(z.enum(CRIME_TYPES)).optional(),
});

export type RegisterDeviceBody = z.infer<typeof registerDeviceSchema>;
export type UnregisterDeviceBody = z.infer<typeof unregisterDeviceSchema>;
export type UpdatePreferencesBody = z.infer<typeof updatePreferencesSchema>;
```

### 7. SNS Client (`backend/api/src/lib/sns.ts`)

Follows the same AWS SDK v3 pattern as `lib/s3.ts`.

```typescript
// backend/api/src/lib/sns.ts

import {
  SNSClient,
  CreatePlatformEndpointCommand,
  PublishCommand,
  DeleteEndpointCommand,
} from '@aws-sdk/client-sns';
import { config } from '../config';
import { logger } from './logger';

const sns = new SNSClient({ region: config.aws.region });

export async function createEndpoint(
  platform: 'ios' | 'android',
  fcmToken: string,
  deviceId: string,
): Promise<string> {
  const platformArn = platform === 'ios' ? config.aws.snsIosArn : config.aws.snsAndroidArn;

  const { EndpointArn } = await sns.send(
    new CreatePlatformEndpointCommand({
      PlatformApplicationArn: platformArn,
      Token: fcmToken,
      CustomUserData: deviceId,
    }),
  );

  if (!EndpointArn) throw new Error('SNS returned no EndpointArn');
  return EndpointArn;
}

export async function deleteEndpoint(endpointArn: string): Promise<void> {
  await sns.send(new DeleteEndpointCommand({ EndpointArn: endpointArn }));
}

export async function publish(
  endpointArn: string,
  platform: 'ios' | 'android',
  notification: { title: string; body: string; data: Record<string, string> },
): Promise<void> {
  const message =
    platform === 'ios'
      ? {
          APNS: JSON.stringify({
            aps: { alert: { title: notification.title, body: notification.body }, sound: 'default', badge: 1 },
            data: notification.data,
          }),
        }
      : {
          GCM: JSON.stringify({
            notification: { title: notification.title, body: notification.body },
            data: notification.data,
          }),
        };

  await sns.send(
    new PublishCommand({
      TargetArn: endpointArn,
      Message: JSON.stringify(message),
      MessageStructure: 'json',
    }),
  );
}

export async function sendToDevice(
  endpointArn: string,
  platform: 'ios' | 'android',
  notification: { title: string; body: string; data: Record<string, string> },
): Promise<boolean> {
  try {
    await publish(endpointArn, platform, notification);
    return true;
  } catch (err: any) {
    if (err.name === 'EndpointDisabledException') {
      logger.warn({ endpointArn }, 'SNS endpoint disabled, will mark subscription inactive');
      return false;
    }
    logger.error({ err, endpointArn }, 'SNS publish failed');
    return false;
  }
}
```

### 8. Route Handlers (`backend/api/src/routes/notifications.ts`)

Direct route handlers on an Express `Router`, exactly like `routes/reports.ts`.

```typescript
// backend/api/src/routes/notifications.ts

import { Router, Request, Response } from 'express';
import { validate } from '../middleware/validate';
import {
  registerDeviceSchema,
  unregisterDeviceSchema,
  updatePreferencesSchema,
} from '../validators/push-subscription';
import { HttpError } from '../lib/errors';
import * as pushModel from '../models/push-subscription';
import * as sns from '../lib/sns';
import { logger } from '../lib/logger';

const router = Router();

router.post('/register', validate(registerDeviceSchema), async (req: Request, res: Response) => {
  const { device_id, fcm_token, platform, lat, lng } = req.body;

  const endpointArn = await sns.createEndpoint(platform, fcm_token, device_id);
  const subscription = await pushModel.upsert({ device_id, fcm_token, platform, lat, lng }, endpointArn);

  logger.info({ device_id, platform }, 'device registered for push');
  res.status(201).json(subscription);
});

router.delete('/unregister', validate(unregisterDeviceSchema), async (req: Request, res: Response) => {
  const { device_id } = req.body;

  const endpointArn = await pushModel.remove(device_id);
  if (endpointArn) {
    await sns.deleteEndpoint(endpointArn).catch((err) =>
      logger.error({ err, endpointArn }, 'failed to delete SNS endpoint'),
    );
  }

  res.json({ message: 'Device unregistered' });
});

router.put('/preferences', validate(updatePreferencesSchema), async (req: Request, res: Response) => {
  const { device_id, enabled, radius, types } = req.body;

  const updated = await pushModel.updatePreferences(device_id, { enabled, radius, types });
  if (!updated) {
    throw HttpError.notFound('No push subscription found for this device');
  }

  res.json(updated);
});

export default router;
```

### 9. Mount the Router (`backend/api/src/routes/index.ts`)

```typescript
// backend/api/src/routes/index.ts (updated)

import { Router } from 'express';
import reportRouter from './reports';
import commentRouter from './comments';
import notificationRouter from './notifications';

const router = Router();

router.get('/', (_req, res) => {
  res.json({ name: 'CrimeReport API', version: '1.0.0' });
});

router.use('/reports', reportRouter);
router.use('/comments', commentRouter);
router.use('/notifications', notificationRouter);

export default router;
```

### 10. Send Notifications on New Report (`backend/api/src/routes/reports.ts`)

Add a fire-and-forget call in the existing `POST /` route handler so creating a report triggers push notifications to nearby devices.

```typescript
// In backend/api/src/routes/reports.ts — add imports:
import * as pushModel from '../models/push-subscription';
import * as sns from '../lib/sns';
import { logger } from '../lib/logger';

// Inside the POST / handler, after res.status(201).json(report):
router.post('/', validate(createReportSchema), async (req: Request, res: Response) => {
  const { device_id, type, description, lat, lng, address } = req.body;

  // ... existing device checks ...
  const report = await reportModel.create({ device_id, type, description, lat, lng, address });
  await deviceActivity.incrementReportCount(device_id);

  res.status(201).json(report);

  // Fire-and-forget: notify nearby devices
  sendNearbyNotifications(report).catch((err) =>
    logger.error({ err, reportId: report.id }, 'push notification batch failed'),
  );
});

async function sendNearbyNotifications(report: {
  id: string;
  device_id: string;
  type: string;
  description: string | null;
  lat: number;
  lng: number;
}) {
  const devices = await pushModel.findNearbyEnabled(report.lat, report.lng, report.type, report.device_id);

  if (devices.length === 0) return;
  logger.info({ reportId: report.id, deviceCount: devices.length }, 'sending push notifications');

  const typeLabel = report.type.charAt(0).toUpperCase() + report.type.slice(1).replace('_', ' ');
  const notification = {
    title: `${typeLabel} Reported Nearby`,
    body: report.description?.substring(0, 100) || 'A new crime was reported in your area',
    data: {
      report_id: report.id,
      type: report.type,
      lat: String(report.lat),
      lng: String(report.lng),
    },
  };

  const results = await Promise.allSettled(
    devices.map(async (device) => {
      const ok = await sns.sendToDevice(device.endpoint_arn!, device.platform, notification);
      if (!ok && device.endpoint_arn) {
        await pushModel.disableByEndpointArn(device.endpoint_arn);
      }
    }),
  );

  const failed = results.filter((r) => r.status === 'rejected').length;
  if (failed > 0) {
    logger.warn({ reportId: report.id, failed, total: devices.length }, 'some push sends failed');
  }
}
```

## API Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/api/v1/notifications/register` | Register device for push notifications |
| DELETE | `/api/v1/notifications/unregister` | Remove device push subscription |
| PUT | `/api/v1/notifications/preferences` | Update notification radius, types, enabled |

## Testing Plan
- Unit tests for `push-subscription` model: `upsert`, `remove`, `updatePreferences`, `findNearbyEnabled`
- Unit tests for `sns` lib: mock AWS SDK, verify `CreatePlatformEndpointCommand`, `PublishCommand`, `DeleteEndpointCommand` calls
- Unit tests for `push-subscription` validator: verify required fields, enum constraints, range limits
- Integration test: `POST /register` → verify row in `push_subscriptions` table and SNS endpoint created
- Integration test: `DELETE /unregister` → verify row removed and SNS endpoint deleted
- Integration test: `PUT /preferences` → verify updated row returned
- Integration test: Create a report near a registered device, verify `sns.sendToDevice` called
- Integration test: Verify the reporter's own device does NOT receive a notification
- Integration test: Disabled endpoints are auto-disabled in the database when SNS returns `EndpointDisabledException`

## Notes
- The `push_subscriptions` table uses a `geography` column for location, consistent with the `reports` table. This allows `ST_DWithin` to use the spatial GIST index for efficient geo-filtering.
- Each device's `radius` column controls how far away reports can be and still trigger a notification. The `findNearbyEnabled` query uses the per-device radius, not a fixed value.
- The `types` column is `TEXT[]` (Postgres array). `NULL` means "all types". The query uses `ANY(types)` for filtering.
- Push sending is fire-and-forget (`catch` on the promise). The HTTP response to the report creator is never delayed by notification delivery.
- When SNS returns `EndpointDisabledException` (user uninstalled the app or revoked notification permission), the subscription is automatically disabled to avoid repeated failures.
- The `@aws-sdk/client-sns` package must be added to `package.json`.

## Files (5 new, 3 updated)
1. `infrastructure/aws/lib/notifications/sns-stack.ts` – **Create** – CDK stack for SNS platform applications
2. `migrations/NNN_push_subscriptions.sql` – **Create** – Database table and spatial index
3. `backend/api/src/lib/sns.ts` – **Create** – AWS SNS SDK v3 wrapper
4. `backend/api/src/models/push-subscription.ts` – **Create** – Model functions (pg pool)
5. `backend/api/src/validators/push-subscription.ts` – **Create** – Zod schemas
6. `backend/api/src/routes/notifications.ts` – **Create** – Route handlers
7. `backend/api/src/routes/index.ts` – **Update** – Mount notification router
8. `backend/api/src/routes/reports.ts` – **Update** – Fire-and-forget push on new report
9. `backend/api/src/config/index.ts` – **Update** – Add SNS ARN env vars
