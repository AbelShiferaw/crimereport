# Milestone 30: Launch Prep

## Status
Not Started

## Goal
Harden the application for production launch — finalize production CDK configuration, validate the existing monitoring stack, complete security review, publish legal pages, add splash/onboarding UX, and prepare all app store assets.

## Dependencies
Requires **Milestone 29** complete (testing & QA passed).
Leverages infrastructure already deployed in Milestones 14–18 (CDK stacks, ECS Fargate, Aurora, monitoring).

## Plan

### 1. Production CDK Configuration Review

The full stack is already defined in `infrastructure/aws/bin/crimereport-stack.ts` with these stacks:

| Stack | File | Purpose |
|-------|------|---------|
| `CrimeReport-Network` | `lib/network/network-stack.ts` | VPC, subnets, NAT Gateway |
| `CrimeReport-Waf` | `lib/network/waf-stack.ts` | WAF WebACL, rate limiting, managed rules |
| `CrimeReport-Security` | `lib/network/security-stack.ts` | Security groups (ALB, ECS, DB, Redis) |
| `CrimeReport-Iam` | `lib/iam/iam-stack.ts` | IAM roles (ECS execution, task) |
| `CrimeReport-Database` | `lib/data/database-stack.ts` | Aurora Serverless v2 PostgreSQL + PostGIS |
| `CrimeReport-Cache` | `lib/data/cache-stack.ts` | ElastiCache Redis |
| `CrimeReport-Media` | `lib/media/media-stack.ts` | S3 + CloudFront, Step Functions (MediaConvert + Rekognition) |
| `CrimeReport-Compute` | `lib/compute/compute-stack.ts` | ECS Fargate, ALB, ECR, auto-scaling |
| `CrimeReport-Monitoring` | `lib/monitoring/monitoring-stack.ts` | CloudWatch alarms + operations dashboard |

**Production hardening tasks:**

- Review and set production-appropriate values for `ECS_MIN_TASKS`, `ECS_MAX_TASKS`, `ECS_CPU`, `ECS_MEMORY` in `lib/config/constants.ts`. Consider starting with `minCapacity: 2` for high availability.
- Verify Aurora Serverless v2 ACU min/max scaling for expected load.
- Confirm WAF rate-limit thresholds in `waf-stack.ts` are appropriate for launch traffic.
- Add an HTTPS listener to the ALB (ACM certificate for `api.reportcrime.app`). Currently only HTTP/80 is configured in `compute-stack.ts`.
- Configure Route 53 hosted zone and alias records for `api.reportcrime.app` and `cdn.reportcrime.app`.
- Enable S3 bucket versioning on the uploads and media buckets for data durability.
- Verify `dbSecret` rotation is configured in `database-stack.ts`.

**HTTPS listener addition** (planned change to `lib/compute/compute-stack.ts`):

```typescript
import * as acm from 'aws-cdk-lib/aws-certificatemanager';

// In ComputeStack constructor:
const certificate = acm.Certificate.fromCertificateArn(
  this, 'ApiCert',
  'arn:aws:acm:us-east-1:ACCOUNT:certificate/CERT_ID',
);

this.alb.addListener('HttpsListener', {
  port: 443,
  protocol: elbv2.ApplicationProtocol.HTTPS,
  certificates: [certificate],
  defaultTargetGroups: [targetGroup],
});

// Redirect HTTP to HTTPS
this.listener.addAction('HttpRedirect', {
  action: elbv2.ListenerAction.redirect({
    protocol: 'HTTPS',
    port: '443',
    permanent: true,
  }),
});
```

### 2. Validate Existing Monitoring Stack

The monitoring stack (`lib/monitoring/monitoring-stack.ts`) already provides:

- **10 CloudWatch Alarms**: DB CPU (>80%), DB connections (>50), DB memory (<256MB), Redis CPU (>80%), Redis memory (>80%), Redis evictions (>100), ECS CPU (>85%), ECS memory (>85%), ALB 5xx (>10), ALB latency (>2s)
- **Operations Dashboard** (`crimereport-operations`): graphs for DB, Redis, ECS, and ALB metrics with alarm annotations and an alarm status widget

**Additional monitoring to add for launch:**

- Add an SNS topic for alarm notifications (email + PagerDuty/Slack webhook).
- **Custom application-level CloudWatch metrics** using **EMF (Embedded Metric Format)** via the `aws-embedded-metrics` library. EMF writes specially formatted JSON to stdout; the CloudWatch agent built into Fargate automatically parses it into real CloudWatch metrics -- no extra SDK calls, no network overhead, no extra infrastructure.

  **Planned custom metrics:**

  | Metric | Type | Description |
  |--------|------|-------------|
  | `ReportsCreated` | Counter | New reports per minute, dimensioned by `CrimeType` |
  | `MediaUploadsCompleted` | Counter | Media files completing the processing pipeline |
  | `MediaFailureRate` | Counter | Media uploads ending in `failed` status |
  | `MediaProcessingLatency` | Timer | Time from upload to `active` status (ms) |
  | `WebSocketConnections` | Gauge | Active Socket.io connections |
  | `BroadcastFanOut` | Counter | Rooms/clients reached per `report:new` broadcast |
  | `RateLimitHits` | Counter | Requests blocked by express-rate-limit (abuse signal) |
  | `GeoGridActivity` | Counter | Reports per grid cell (for heat map / hot-spot analysis) |

  **Example usage** (to be added in route handlers):

  ```typescript
  import { createMetricsLogger, Unit } from 'aws-embedded-metrics';

  const metrics = createMetricsLogger();
  metrics.setNamespace('CrimeReport');
  metrics.putDimensions({ CrimeType: report.type });
  metrics.putMetric('ReportsCreated', 1, Unit.Count);
  await metrics.flush();
  ```

  EMF is preferred over the CloudWatch SDK (`PutMetricData`) because it adds zero latency to HTTP requests and over CloudWatch Logs metric filters because it supports dimensions, units, and high-resolution metrics natively.

- Add a dashboard row for these custom application-level metrics.
- Configure CloudWatch Log Insights saved queries for common debugging patterns.
- Create alarms on key custom metrics (e.g., `MediaFailureRate` exceeding a threshold).

```typescript
import * as sns from 'aws-cdk-lib/aws-sns';
import * as snsSubscriptions from 'aws-cdk-lib/aws-sns-subscriptions';
import * as actions from 'aws-cdk-lib/aws-cloudwatch-actions';

const alarmTopic = new sns.Topic(this, 'AlarmTopic', {
  topicName: `${PROJECT_PREFIX}-alarms`,
});

alarmTopic.addSubscription(
  new snsSubscriptions.EmailSubscription('ops@reportcrime.app'),
);

// Attach to all existing alarms
for (const alarm of [dbCpuAlarm, dbConnectionsAlarm, /* ... all 10 ... */]) {
  alarm.addAlarmAction(new actions.SnsAction(alarmTopic));
  alarm.addOkAction(new actions.SnsAction(alarmTopic));
}
```

### 3. Security Review

**Backend security checklist:**

- [ ] Helmet middleware is active (`backend/api/src/app.ts` — already configured)
- [ ] CORS origin is locked to production domain (verify `config.corsOrigin`)
- [ ] Rate limiting on report creation (already `MAX_DAILY_REPORTS = 10` per device in `routes/reports.ts`)
- [ ] Rate limiting on comment creation (already `MAX_DAILY_COMMENTS = 50` per device)
- [ ] Device flagging prevents abuse (already checks `device.flagged` before create/upload)
- [ ] WAF rate limiting on ALB (already in `waf-stack.ts`)
- [ ] S3 presigned URL expiration is reasonable (verify in `lib/s3.ts`)
- [ ] Database credentials stored in Secrets Manager (already — `dbSecret` injected via ECS secrets)
- [ ] No secrets in environment variables or source code
- [ ] Zod validation on all request inputs (already — `validate` middleware on every route)
- [ ] SQL injection prevention (already — parameterized queries via `pg` pool in all models)
- [ ] Content moderation pipeline active (Rekognition in Step Functions media pipeline)

**Infrastructure security checklist:**

- [ ] ECS tasks in private subnets with no public IP (already — `AssignPublicIp: DISABLED` in `compute-stack.ts`)
- [ ] DB and Redis security groups only allow ECS ingress (verify in `security-stack.ts`)
- [ ] ALB security group restricts to 80/443 ingress
- [ ] ECR image scanning on push (already — `imageScanOnPush: true`)
- [ ] CloudWatch logs encrypted at rest
- [ ] S3 bucket public access blocked (verify `blockPublicAccess` on uploads and media buckets)

### 4. Production Environment Variables

Create environment configuration for the ECS task definition. These values are already partially set in `compute-stack.ts` — verify completeness:

```typescript
// Already configured in compute-stack.ts container environment:
environment: {
  NODE_ENV: 'production',
  PORT: '3000',
  REDIS_HOST: redisEndpoint,
  REDIS_PORT: redisPort,
  S3_UPLOADS_BUCKET: s3UploadsBucket,
  S3_MEDIA_BUCKET: s3MediaBucket,
  CDN_DOMAIN: cdnDomain,
},
secrets: {
  DATABASE_URL: ecs.Secret.fromSecretsManager(dbSecret),
},
```

**Additional env vars to add:**

```typescript
environment: {
  // ... existing ...
  LOG_LEVEL: 'info',
  CORS_ORIGIN: 'https://reportcrime.app',
  WS_PING_INTERVAL: '25000',
  WS_PING_TIMEOUT: '5000',
},
```

### 5. Database Migration for Production

Run `node-pg-migrate` against the production Aurora cluster. Migrations live in `backend/api/migrations/`.

```bash
# From backend/api/
DATABASE_URL=$PRODUCTION_DATABASE_URL npm run migrate:up
```

Verify PostGIS extension is enabled, spatial indexes exist on the `reports` table, and all migration files have been applied.

### 6. Flutter Production Build Configuration

Create or update `apps/mobile/lib/core/config/environment.dart`:

```dart
enum Environment { dev, staging, prod }

class AppConfig {
  static Environment get environment {
    const env = String.fromEnvironment('ENV', defaultValue: 'dev');
    switch (env) {
      case 'prod':
        return Environment.prod;
      case 'staging':
        return Environment.staging;
      default:
        return Environment.dev;
    }
  }

  static String get apiBaseUrl {
    switch (environment) {
      case Environment.prod:
        return 'https://api.reportcrime.app';
      case Environment.staging:
        return 'https://staging-api.reportcrime.app';
      case Environment.dev:
        return 'http://localhost:3000';
    }
  }

  static String get wsBaseUrl {
    switch (environment) {
      case Environment.prod:
        return 'wss://api.reportcrime.app';
      case Environment.staging:
        return 'wss://staging-api.reportcrime.app';
      case Environment.dev:
        return 'ws://localhost:3000';
    }
  }
}
```

### 7. App Store Assets

**iOS App Store:**

```
assets/app_store/ios/
├── icon_1024x1024.png
├── screenshots/
│   ├── 6.7_inch/          # iPhone 15 Pro Max (1290×2796)
│   │   ├── 01_feed.png
│   │   ├── 02_map.png
│   │   ├── 03_submit.png
│   │   └── 04_settings.png
│   └── 6.1_inch/          # iPhone 15 Pro (1179×2556)
└── promotional_text.txt
```

**Google Play Store:**

```
assets/app_store/android/
├── icon_512x512.png
├── feature_graphic_1024x500.png
├── screenshots/
│   └── phone/
│       ├── 01_feed.png
│       ├── 02_map.png
│       ├── 03_submit.png
│       └── 04_settings.png
├── short_description.txt   # 80 chars max
└── full_description.txt    # 4000 chars max
```

### 8. Privacy Policy & Terms of Service

Publish at `https://reportcrime.app/privacy` and `https://reportcrime.app/terms`.

Key disclosures for app store compliance:

- **Data collected**: anonymous device identifier (UUID), location (when in use), user-submitted photos/videos/text
- **Data NOT collected**: name, email, phone, Apple ID, Google account, browsing history
- **Third-party services**: AWS (hosting, storage, CDN, media processing), Mapbox (map tiles)
- **Data retention**: reports retained indefinitely; device identifiers can be reset by reinstalling
- **Content moderation**: automated via AWS Rekognition; manual review for flagged content

### 9. Splash Screen & Onboarding

**Splash screen** (`apps/mobile/lib/features/splash/presentation/splash_screen.dart`):

- Animated app logo with fade-in
- Check API connectivity via `/health/ready`
- Navigate to onboarding (first launch) or `AppShell` (returning user)

**Onboarding** (`apps/mobile/lib/features/onboarding/presentation/onboarding_screen.dart`):

- Page 1: "Report Anonymously" — explain no-account design
- Page 2: "Stay Informed" — show feed/map preview
- Page 3: Permissions — request Location (when in use), Camera, Notifications with clear explanations
- Store `onboarding_complete` flag in `shared_preferences`

### 10. Final Polish

- Remove all debug prints and `TODO` comments from production code paths
- Verify Pino log level is `info` in production (not `debug` or `trace`)
- Confirm `flutter build` with `--release` produces no warnings
- Test deep link handling if applicable
- Verify app icon renders correctly on both platforms
- Test dark mode / light mode if supported (current theme in `apps/mobile/lib/core/theme/`)

## Deliverable Checklist
- [ ] HTTPS listener added to ALB with ACM certificate
- [ ] Route 53 DNS configured for API and CDN domains
- [ ] ECS task count and scaling reviewed for production load
- [ ] Aurora Serverless v2 ACU limits set for production
- [ ] SNS alarm notifications configured and tested
- [ ] Security review checklist completed (all items passed)
- [ ] Production database migrations applied successfully
- [ ] Environment configuration deployed via CDK
- [ ] App store screenshots captured for all required sizes
- [ ] Privacy policy and terms of service published
- [ ] Splash screen and onboarding flow implemented
- [ ] All debug code and verbose logging removed
- [ ] Production build compiles cleanly on both platforms

## Notes
- **Monitoring is already substantial** — the existing `monitoring-stack.ts` covers DB, Redis, ECS, and ALB with 10 alarms and an operations dashboard. This milestone adds notification routing and application-level metrics.
- **No CI/CD yet** — production deploys are manual via `cdk deploy --all`. Milestone 24.5 will automate this.
- **HTTPS requires an ACM certificate** — must be in `us-east-1` for CloudFront, and the same region as the ALB for the API. Request and validate the cert before deploying.
- **Mapbox API key** — ensure the production token is configured in the Flutter app's `.env` and has appropriate usage limits.
- **Consider a staging environment** — deploy the same CDK stacks with a different prefix (e.g., `crimereport-staging`) for pre-production validation.

## Files (estimated 10 new/modified)
1. `infrastructure/aws/lib/compute/compute-stack.ts` — add HTTPS listener, HTTP redirect
2. `infrastructure/aws/lib/monitoring/monitoring-stack.ts` — add SNS topic, alarm actions, custom metrics
3. `infrastructure/aws/lib/config/constants.ts` — update production scaling values
4. `apps/mobile/lib/core/config/environment.dart` — new
5. `apps/mobile/lib/features/splash/presentation/splash_screen.dart` — new
6. `apps/mobile/lib/features/onboarding/presentation/onboarding_screen.dart` — new
7. `docs/privacy-policy.md` — new
8. `docs/terms-of-service.md` — new
9. `assets/app_store/ios/*` — new (screenshots, icon)
10. `assets/app_store/android/*` — new (screenshots, icon, feature graphic)
