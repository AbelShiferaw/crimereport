# Milestone 29: Testing & QA

## Status
Not Started

## Goal
Achieve comprehensive test coverage across the entire stack — backend API routes and models (Jest + Supertest), CDK infrastructure assertions, Flutter unit/widget/integration tests — and establish integration testing against a deployed staging environment.

## Dependencies
Requires **Milestones 25–28** complete (full Flutter ↔ backend integration).
Builds on the existing test suites already created alongside prior milestones.

## Plan

### 1. Audit & Extend Backend Unit Tests

Existing model tests live in `backend/api/src/__tests__/models/` (e.g. `report.test.ts`, `media.test.ts`, `comment.test.ts`, `device-activity.test.ts`, `report-upvote.test.ts`, `comment-flag.test.ts`). Each mocks `../../lib/db` and asserts on raw SQL via `db.query`.

**Gaps to close:**

- Add edge-case coverage for `findNearby` with zero results, boundary radius, and PostGIS `ST_DWithin` parameter ordering.
- Add tests for any models created in Milestones 25–28 (e.g. notification tokens, WebSocket session tracking).
- Verify all `GREATEST(... - 1, 0)` floor guards in decrement functions.

**Pattern to follow** (from `backend/api/src/__tests__/models/report.test.ts`):

```typescript
import * as reportModel from '../../models/report';
import * as db from '../../lib/db';

jest.mock('../../lib/db');

const mockQuery = db.query as jest.MockedFunction<typeof db.query>;

describe('report model', () => {
  beforeEach(() => jest.clearAllMocks());

  it('queries with PostGIS ST_DWithin and returns rows', async () => {
    mockQuery.mockResolvedValueOnce({ rows: fakeRows, rowCount: 2 } as any);

    const result = await reportModel.findNearby(40.7128, -74.006, 5000, { limit: 10, offset: 0 });

    expect(result).toHaveLength(2);
    expect(mockQuery).toHaveBeenCalledWith(
      expect.stringContaining('ST_DWithin'),
      [40.7128, -74.006, 5000, 10, 0],
    );
  });
});
```

### 2. Audit & Extend Backend Route Tests

Existing route tests live in `backend/api/src/__tests__/routes/` (e.g. `reports.test.ts`, `comments.test.ts`, `health.test.ts`, `media-upload.test.ts`). Each mocks model modules and uses Supertest against the Express `app` export.

**Gaps to close:**

- Add tests for the WebSocket gateway (Socket.io events: `new_report`, `new_comment`, `upvote_change`). Use `socket.io-client` in tests connecting to an `httpServer` instance.
- Add tests for any push-notification dispatch endpoints added in Milestone 24.
- Validate all Zod schemas reject malformed input (already partial — extend for new schemas).

**Pattern to follow** (from `backend/api/src/__tests__/routes/reports.test.ts`):

```typescript
import * as reportModel from '../../models/report';
import * as deviceActivity from '../../models/device-activity';

jest.mock('../../models/report');
jest.mock('../../models/device-activity');

const mockReport = reportModel as jest.Mocked<typeof reportModel>;
const mockDevice = deviceActivity as jest.Mocked<typeof deviceActivity>;

import request from 'supertest';
import app from '../../app';

describe('POST /api/v1/reports', () => {
  it('returns 429 when daily limit is exceeded', async () => {
    mockDevice.getOrCreate.mockResolvedValueOnce({ ...fakeDevice, report_count_today: 10 });

    const res = await request(app).post('/api/v1/reports').send(validBody);

    expect(res.status).toBe(429);
    expect(res.body.error).toContain('limit');
  });
});
```

**New: Socket.io integration test:**

```typescript
import { createServer } from 'http';
import { Server } from 'socket.io';
import { io as ioClient, Socket as ClientSocket } from 'socket.io-client';
import app from '../../app';
import { attachSocketHandlers } from '../../socket';

describe('WebSocket events', () => {
  let httpServer: ReturnType<typeof createServer>;
  let clientSocket: ClientSocket;

  beforeAll((done) => {
    httpServer = createServer(app);
    const io = new Server(httpServer);
    attachSocketHandlers(io);
    httpServer.listen(() => {
      const port = (httpServer.address() as any).port;
      clientSocket = ioClient(`http://localhost:${port}`);
      clientSocket.on('connect', done);
    });
  });

  afterAll(() => {
    clientSocket.disconnect();
    httpServer.close();
  });

  it('receives new_report event when report is created', (done) => {
    clientSocket.on('new_report', (data) => {
      expect(data).toHaveProperty('id');
      done();
    });
    // trigger via HTTP POST
  });
});
```

### 3. Audit & Extend CDK Infrastructure Tests

Existing CDK tests live in `infrastructure/aws/test/` with one file per stack (e.g. `compute-stack.test.ts`, `monitoring-stack.test.ts`, `database-stack.test.ts`, `waf-stack.test.ts`, `network-stack.test.ts`, etc.). They use `aws-cdk-lib/assertions` (`Template`, `Match`).

**Gaps to close:**

- Add `media-stack.test.ts` assertions for the Step Functions state machine (MediaConvert + Rekognition pipeline), S3 bucket policies, and CloudFront distribution configuration.
- Add cross-stack dependency smoke tests: synthesize the full app (`bin/crimereport-stack.ts`) and verify no circular references.
- Validate WAF rule priorities and rate-limit thresholds.

**Pattern to follow** (from `infrastructure/aws/test/compute/compute-stack.test.ts`):

```typescript
import * as cdk from 'aws-cdk-lib';
import { Template, Match } from 'aws-cdk-lib/assertions';
import { ComputeStack } from '../../lib/compute/compute-stack';

describe('ComputeStack', () => {
  let template: Template;

  beforeAll(() => {
    const app = new cdk.App();
    // ... set up dependency stubs ...
    const stack = new ComputeStack(app, 'TestCompute', { /* props */ });
    template = Template.fromStack(stack);
  });

  test('creates Fargate service with correct config', () => {
    template.hasResourceProperties('AWS::ECS::Service', {
      ServiceName: 'crimereport-api',
      LaunchType: 'FARGATE',
      DesiredCount: 1,
    });
  });
});
```

**New: Full-synthesis smoke test:**

```typescript
import * as cdk from 'aws-cdk-lib';

describe('Full CDK synthesis', () => {
  test('synthesizes all stacks without errors', () => {
    expect(() => {
      // Re-use the logic from bin/crimereport-stack.ts
      const app = new cdk.App();
      // ... instantiate all stacks ...
      app.synth();
    }).not.toThrow();
  });
});
```

### 4. Audit & Extend Flutter Unit Tests

Existing Flutter tests live in `apps/mobile/test/` mirroring the `lib/` structure:

| Area | Existing test file |
|------|-------------------|
| Report model | `test/features/feed/data/models/report_test.dart` |
| Media model | `test/features/feed/data/models/media_test.dart` |
| Comment model | `test/features/feed/data/models/comment_test.dart` |
| Feed providers | `test/features/feed/providers/feed_providers_test.dart` |
| Map providers | `test/features/map/providers/map_providers_test.dart` |
| Settings providers | `test/features/settings/providers/settings_providers_test.dart` |
| Enums | `test/core/constants/enums_test.dart` |
| Formatters | `test/core/utils/formatters_test.dart` |
| Geo utils | `test/core/utils/geo_utils_test.dart` |
| Mock data service | `test/shared/data/mock_data_service_test.dart` |

**Gaps to close:**

- Add tests for the Dio HTTP client wrapper / API service (mock Dio responses with `dio` interceptors or a test adapter).
- Add tests for the `socket_io_client` real-time provider (mock socket events).
- Add tests for camera/media submission flow state management.
- Add tests for permission handling logic.

**Pattern to follow** (from `apps/mobile/test/features/feed/providers/feed_providers_test.dart`):

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crimereport/features/feed/providers/feed_providers.dart';

void main() {
  test('filters reports by selected crime type', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(crimeTypeFiltersProvider.notifier).state = {
      ReportType.theft,
    };

    final reports = await container.read(feedReportsProvider.future);
    for (final report in reports) {
      expect(report.type, ReportType.theft);
    }
  });
}
```

### 5. Flutter Widget Tests

**New tests to create:**

- `test/features/feed/presentation/widgets/feed_video_item_test.dart` — verify report info renders, double-tap upvote triggers callback.
- `test/features/feed/presentation/widgets/comments_sheet_test.dart` — verify comment list renders, submit sends content.
- `test/features/submit/presentation/submit_screen_test.dart` — verify form validation, crime type selection.
- `test/shared/widgets/floating_nav_bar_test.dart` — verify tab switching.

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crimereport/features/feed/presentation/widgets/feed_video_item.dart';

void main() {
  testWidgets('FeedVideoItem displays report description', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: FeedVideoItem(report: testReport, isActive: false),
          ),
        ),
      ),
    );

    expect(find.text('Test description'), findsOneWidget);
  });
}
```

### 6. Flutter Integration Tests (E2E)

Create `apps/mobile/integration_test/app_test.dart` for on-device testing against a running staging backend.

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:crimereport/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Feed loads and displays reports', (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 5));

    expect(find.byType(PageView), findsOneWidget);
  });

  testWidgets('Navigation between feed, map, and submit works', (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 3));

    await tester.tap(find.text('Map'));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    // MapScreen should be visible

    await tester.tap(find.text('Report'));
    await tester.pumpAndSettle();
    // CameraScreen or SubmitScreen should be visible
  });
}
```

### 7. Backend Integration Tests Against Staging

Create `backend/api/src/__tests__/integration/staging.test.ts` to validate deployed endpoints. These run against a real staging environment (not mocked).

```typescript
import request from 'supertest';

const STAGING_URL = process.env.STAGING_URL ?? 'https://staging-api.reportcrime.app';

describe('Staging API smoke tests', () => {
  it('GET /health returns 200', async () => {
    const res = await request(STAGING_URL).get('/health');
    expect(res.status).toBe(200);
    expect(res.body.status).toBe('ok');
  });

  it('GET /health/ready confirms DB and Redis connectivity', async () => {
    const res = await request(STAGING_URL).get('/health/ready');
    expect(res.status).toBe(200);
    expect(res.body.checks.db).toBe('connected');
    expect(res.body.checks.redis).toBe('connected');
  });

  it('GET /api/v1/reports returns nearby reports', async () => {
    const res = await request(STAGING_URL)
      .get('/api/v1/reports')
      .query({ lat: 40.7128, lng: -74.006, radius: 5000 });
    expect(res.status).toBe(200);
    expect(res.body).toHaveProperty('data');
    expect(res.body).toHaveProperty('meta');
  });
});
```

### 8. Load Testing

Create `backend/api/load-tests/nearby-reports.k6.ts` using k6 for load testing the most critical endpoint.

```javascript
import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  stages: [
    { duration: '30s', target: 50 },
    { duration: '1m', target: 100 },
    { duration: '30s', target: 0 },
  ],
  thresholds: {
    http_req_duration: ['p(95)<500'],
    http_req_failed: ['rate<0.01'],
  },
};

export default function () {
  const lat = 40.7128 + (Math.random() - 0.5) * 0.1;
  const lng = -74.006 + (Math.random() - 0.5) * 0.1;

  const res = http.get(
    `${__ENV.API_URL}/api/v1/reports?lat=${lat}&lng=${lng}&radius=5000`,
  );

  check(res, {
    'status is 200': (r) => r.status === 200,
    'response time < 500ms': (r) => r.timings.duration < 500,
    'has data array': (r) => JSON.parse(r.body).data !== undefined,
  });

  sleep(1);
}
```

### 9. Test Configuration & Scripts

**Backend** (`backend/api/jest.config.ts` — already configured):

```typescript
import type { Config } from 'jest';

const config: Config = {
  preset: 'ts-jest',
  testEnvironment: 'node',
  roots: ['<rootDir>/src'],
  testMatch: ['**/__tests__/**/*.test.ts'],
  clearMocks: true,
};

export default config;
```

Add a coverage script to `backend/api/package.json`:

```json
{
  "scripts": {
    "test": "jest",
    "test:coverage": "jest --coverage",
    "test:staging": "STAGING_URL=$STAGING_URL jest --testPathPattern=integration/staging"
  }
}
```

**Infrastructure** (`infrastructure/aws/jest.config.js` — already configured):

```javascript
module.exports = {
  testEnvironment: 'node',
  roots: ['<rootDir>/test'],
  testMatch: ['**/*.test.ts'],
  transform: { '^.+\\.tsx?$': 'ts-jest' },
};
```

**Flutter** — tests run with `flutter test` from `apps/mobile/`. Integration tests run with:

```bash
cd apps/mobile
flutter test                                        # unit + widget tests
flutter test integration_test/app_test.dart         # integration tests (on device/emulator)
```

## Test Coverage Targets

| Component | Target | Current Baseline |
|-----------|--------|-----------------|
| Backend models (`src/__tests__/models/`) | 90% | ~80% (6 test files) |
| Backend routes (`src/__tests__/routes/`) | 85% | ~70% (4 test files) |
| CDK stacks (`infrastructure/aws/test/`) | 80% | ~75% (9 test files) |
| Flutter models (`test/**/models/`) | 90% | ~85% (3 test files) |
| Flutter providers (`test/**/providers/`) | 80% | ~60% (3 test files) |
| Flutter widgets (new) | 70% | 0% |
| API integration (staging) | 100% of endpoints | 0% |

## Deliverable Checklist
- [ ] All existing backend model tests passing with extended coverage
- [ ] All existing backend route tests passing with WebSocket tests added
- [ ] All CDK infrastructure tests passing with media-stack and synthesis tests added
- [ ] All existing Flutter unit tests passing with API/socket provider tests added
- [ ] Flutter widget tests created and passing for key screens
- [ ] Flutter integration test runs on iOS simulator and Android emulator
- [ ] Backend staging integration tests passing against deployed environment
- [ ] Load test confirms <500ms p95 latency at 100 concurrent users
- [ ] `jest --coverage` meets targets for backend and infrastructure
- [ ] `flutter test --coverage` meets targets for mobile app
- [ ] Test scripts documented in respective package.json / README

## Notes
- **No CI/CD yet** — Milestone 24.5 will set up GitHub Actions to run these tests on PR. For now, all tests run locally.
- **Mocking strategy**: Backend tests mock at the `db.query` level (model tests) or at the model-module level (route tests). Flutter tests use `ProviderContainer` overrides. CDK tests synthesize stacks with stub dependencies.
- **Integration tests require a running staging environment** — coordinate with infrastructure deployment before running `test:staging`.
- **Socket.io tests** may need increased Jest timeout (`jest.setTimeout(10000)`) due to connection handshake.
- **Flutter widget tests** that depend on Mapbox will need the `mapbox_maps_flutter` widget to be wrapped or stubbed, as it requires native platform channels.

## Files (estimated 12 new/modified)
1. `backend/api/src/__tests__/routes/websocket.test.ts` — new
2. `backend/api/src/__tests__/integration/staging.test.ts` — new
3. `backend/api/package.json` — add test:coverage and test:staging scripts
4. `infrastructure/aws/test/media/media-stack.test.ts` — extend
5. `infrastructure/aws/test/synthesis.test.ts` — new
6. `apps/mobile/test/features/feed/presentation/widgets/feed_video_item_test.dart` — new
7. `apps/mobile/test/features/feed/presentation/widgets/comments_sheet_test.dart` — new
8. `apps/mobile/test/features/submit/presentation/submit_screen_test.dart` — new
9. `apps/mobile/test/shared/widgets/floating_nav_bar_test.dart` — new
10. `apps/mobile/integration_test/app_test.dart` — new
11. `backend/api/load-tests/nearby-reports.k6.ts` — new
12. Existing test files — extend with additional cases
