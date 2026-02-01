# Milestone 29: Testing

## Goal
Comprehensive testing of the full application - unit tests, integration tests, and end-to-end testing.

## Dependencies
Requires **Milestones 25-28** complete (full integration).

## Implementation

### 1. Flutter Unit Tests

**Report Model Tests:**
```dart
// test/models/report_test.dart

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Report Model', () {
    test('fromJson creates valid Report', () {
      final json = {
        'id': 'uuid-123',
        'type': 'theft',
        'description': 'Test description',
        'latitude': 37.7749,
        'longitude': -122.4194,
        'upvotes': 10,
        'comment_count': 5,
        'created_at': '2024-01-15T10:00:00Z',
      };
      
      final report = Report.fromJson(json);
      
      expect(report.id, 'uuid-123');
      expect(report.type, ReportType.theft);
      expect(report.latitude, 37.7749);
      expect(report.upvotes, 10);
    });
    
    test('toJson creates valid JSON', () {
      final report = Report(
        id: 'uuid-123',
        type: ReportType.assault,
        latitude: 37.7749,
        longitude: -122.4194,
        // ...
      );
      
      final json = report.toJson();
      
      expect(json['type'], 'assault');
      expect(json['latitude'], 37.7749);
    });
  });
}
```

**Provider Tests:**
```dart
// test/providers/report_providers_test.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockReportRepository extends Mock implements ReportRepository {}

void main() {
  late MockReportRepository mockRepo;
  late ProviderContainer container;
  
  setUp(() {
    mockRepo = MockReportRepository();
    container = ProviderContainer(
      overrides: [
        reportRepositoryProvider.overrideWithValue(mockRepo),
      ],
    );
  });
  
  tearDown(() => container.dispose());
  
  test('nearbyReportsProvider returns reports', () async {
    final mockReports = [
      Report(id: '1', type: ReportType.theft, /* ... */),
      Report(id: '2', type: ReportType.assault, /* ... */),
    ];
    
    when(() => mockRepo.getNearbyReports(any(), any()))
        .thenAnswer((_) async => mockReports);
    
    final result = await container.read(
      nearbyReportsProvider(LatLng(37.77, -122.41)).future
    );
    
    expect(result.length, 2);
    expect(result[0].id, '1');
  });
}
```

### 2. Flutter Widget Tests
```dart
// test/widgets/feed_video_item_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('FeedVideoItem displays report info', (tester) async {
    final report = Report(
      id: 'test-id',
      type: ReportType.theft,
      description: 'Test crime description',
      upvotes: 42,
      commentCount: 7,
      // ...
    );
    
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FeedVideoItem(report: report, isActive: true),
        ),
      ),
    );
    
    // Verify UI elements
    expect(find.text('THEFT'), findsOneWidget);
    expect(find.text('Test crime description'), findsOneWidget);
    expect(find.text('42'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
  });
  
  testWidgets('Double tap triggers upvote', (tester) async {
    bool upvoteCalled = false;
    
    await tester.pumpWidget(
      MaterialApp(
        home: FeedVideoItem(
          report: testReport,
          isActive: true,
          onUpvote: () => upvoteCalled = true,
        ),
      ),
    );
    
    await tester.tap(find.byType(FeedVideoItem));
    await tester.pump(Duration(milliseconds: 50));
    await tester.tap(find.byType(FeedVideoItem));
    await tester.pump();
    
    expect(upvoteCalled, true);
  });
}
```

### 3. Backend Unit Tests
```javascript
// backend/tests/services/reportService.test.js

const { describe, it, expect, beforeEach, jest } = require('@jest/globals');
const reportService = require('../../src/services/reportService');
const reportRepository = require('../../src/repositories/reportRepository');

jest.mock('../../src/repositories/reportRepository');

describe('ReportService', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });
  
  describe('getNearbyReports', () => {
    it('returns reports within radius', async () => {
      const mockReports = [
        { id: '1', type: 'theft', latitude: 37.77, longitude: -122.41 },
        { id: '2', type: 'assault', latitude: 37.78, longitude: -122.42 },
      ];
      
      reportRepository.findNearby.mockResolvedValue(mockReports);
      
      const result = await reportService.getNearbyReports(37.77, -122.41, 10000, 50, 'device-123');
      
      expect(result.length).toBe(2);
      expect(reportRepository.findNearby).toHaveBeenCalledWith(37.77, -122.41, 10000, 50);
    });
  });
  
  describe('createReport', () => {
    it('creates report and invalidates cache', async () => {
      const reportData = {
        device_id: 'device-123',
        type: 'theft',
        description: 'Test',
        latitude: 37.77,
        longitude: -122.41,
      };
      
      reportRepository.createWithLocation.mockResolvedValue({
        id: 'new-id',
        ...reportData,
      });
      
      const result = await reportService.createReport(reportData);
      
      expect(result.id).toBe('new-id');
      expect(reportRepository.createWithLocation).toHaveBeenCalled();
    });
    
    it('throws error when rate limited', async () => {
      // Mock rate limit exceeded
      jest.spyOn(reportService, 'checkReportRateLimit')
          .mockRejectedValue(new Error('Rate limit exceeded'));
      
      await expect(reportService.createReport({}))
          .rejects.toThrow('Rate limit exceeded');
    });
  });
});
```

### 4. Backend Integration Tests
```javascript
// backend/tests/integration/reports.test.js

const request = require('supertest');
const app = require('../../src/app');
const { initDatabase } = require('../../src/config/database');
const { initRedis } = require('../../src/config/redis');

describe('Reports API', () => {
  beforeAll(async () => {
    await initDatabase();
    await initRedis();
  });
  
  describe('GET /api/v1/reports/nearby', () => {
    it('returns 200 with reports', async () => {
      const response = await request(app)
        .get('/api/v1/reports/nearby')
        .query({ lat: 37.7749, lng: -122.4194 })
        .set('X-Device-ID', 'test-device-123')
        .expect(200);
      
      expect(response.body.data).toBeInstanceOf(Array);
      expect(response.body.meta).toHaveProperty('lat', 37.7749);
    });
    
    it('returns 400 without location', async () => {
      await request(app)
        .get('/api/v1/reports/nearby')
        .set('X-Device-ID', 'test-device-123')
        .expect(400);
    });
  });
  
  describe('POST /api/v1/reports', () => {
    it('creates a new report', async () => {
      const response = await request(app)
        .post('/api/v1/reports')
        .set('X-Device-ID', 'test-device-123')
        .send({
          type: 'theft',
          description: 'Test report',
          latitude: 37.7749,
          longitude: -122.4194,
        })
        .expect(201);
      
      expect(response.body.data).toHaveProperty('id');
      expect(response.body.data.type).toBe('theft');
    });
  });
});
```

### 5. End-to-End Tests (Flutter)
```dart
// integration_test/app_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  
  group('Full App Flow', () {
    testWidgets('User can view and interact with feed', (tester) async {
      app.main();
      await tester.pumpAndSettle();
      
      // Wait for feed to load
      await tester.pumpAndSettle(Duration(seconds: 3));
      
      // Verify feed is showing
      expect(find.byType(FeedVideoItem), findsWidgets);
      
      // Tap upvote button
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded).first);
      await tester.pumpAndSettle();
      
      // Navigate to map
      await tester.tap(find.text('Map'));
      await tester.pumpAndSettle(Duration(seconds: 2));
      
      // Verify map is showing
      expect(find.byType(MapboxMap), findsOneWidget);
    });
    
    testWidgets('User can submit a report', (tester) async {
      app.main();
      await tester.pumpAndSettle();
      
      // Navigate to submit tab
      await tester.tap(find.text('Report'));
      await tester.pumpAndSettle();
      
      // This would require camera mocking in a real test
      // For now, verify the submit screen loads
      expect(find.byType(CameraScreen), findsOneWidget);
    });
  });
}
```

### 6. Load Testing (Backend)
```javascript
// backend/tests/load/reports.js (k6 script)

import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  stages: [
    { duration: '30s', target: 50 },   // Ramp up
    { duration: '1m', target: 100 },   // Hold
    { duration: '30s', target: 0 },    // Ramp down
  ],
};

export default function () {
  // Random location in SF
  const lat = 37.7749 + (Math.random() - 0.5) * 0.1;
  const lng = -122.4194 + (Math.random() - 0.5) * 0.1;
  
  const res = http.get(
    `${__ENV.API_URL}/api/v1/reports/nearby?lat=${lat}&lng=${lng}`,
    {
      headers: { 'X-Device-ID': `load-test-${__VU}-${__ITER}` },
    }
  );
  
  check(res, {
    'status is 200': (r) => r.status === 200,
    'response time < 500ms': (r) => r.timings.duration < 500,
  });
  
  sleep(1);
}
```

## Test Coverage Targets

| Component | Target |
|-----------|--------|
| Flutter Models | 90% |
| Flutter Providers | 80% |
| Flutter Widgets | 70% |
| Backend Services | 85% |
| Backend Controllers | 80% |
| API Integration | 100% endpoints |

## Deliverable Checklist
- [ ] Flutter unit tests for models pass
- [ ] Flutter provider tests pass
- [ ] Flutter widget tests pass
- [ ] Backend unit tests pass
- [ ] Backend integration tests pass
- [ ] E2E test runs on simulator
- [ ] Load test shows <500ms p95
- [ ] Test coverage meets targets
- [ ] All critical paths tested
- [ ] CI pipeline runs tests on PR

## Files (8 total)
1. `test/models/report_test.dart`
2. `test/providers/report_providers_test.dart`
3. `test/widgets/feed_video_item_test.dart`
4. `integration_test/app_test.dart`
5. `backend/tests/services/reportService.test.js`
6. `backend/tests/integration/reports.test.js`
7. `backend/tests/load/reports.js`
8. `.github/workflows/test.yml` - CI config
