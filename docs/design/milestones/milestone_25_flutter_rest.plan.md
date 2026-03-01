# Milestone 25: Flutter ↔ REST API

## Status
Not Started

## Goal
Replace `MockDataService` with real REST API calls using **dio** (already in pubspec). Introduce an `ApiClient` service layer and per-feature repositories, update existing Riverpod providers to fetch from the live backend, and add proper error/loading state handling across the feed, map, and submit features.

## Dependencies
- **Milestone 13** – Flutter app feature-complete with mock data
- **Milestone 17** – ECS Fargate backend deployed
- **Milestone 15** – Database migrations applied (reports, comments, media, upvotes tables)

## Plan

### 1. API Client (shared service)

Create a centralized dio wrapper that every repository uses. Reads `apiBaseUrl` from `AppConstants` (already defined) and attaches the anonymous device ID header.

```dart
// lib/shared/data/api/api_client.dart

import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:crimereport/core/constants/app_constants.dart';
import 'package:crimereport/features/settings/providers/settings_providers.dart';

class ApiClient {
  late final Dio dio;

  ApiClient({required String baseUrl, required String deviceId}) {
    dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
      headers: {
        HttpHeaders.contentTypeHeader: 'application/json',
        'X-Device-ID': deviceId,
      },
    ));

    if (kDebugMode) {
      dio.interceptors.add(LogInterceptor(requestBody: true, responseBody: true));
    }

    dio.interceptors.add(InterceptorsWrapper(
      onError: (error, handler) {
        if (error.response?.statusCode == 429) {
          handler.reject(DioException(
            requestOptions: error.requestOptions,
            error: const RateLimitException(),
            type: DioExceptionType.badResponse,
          ));
          return;
        }
        handler.next(error);
      },
    ));
  }
}

class RateLimitException implements Exception {
  const RateLimitException();
}

final apiClientProvider = Provider<ApiClient>((ref) {
  final deviceId = ref.watch(anonymousIdProvider).valueOrNull ?? '';
  return ApiClient(
    baseUrl: AppConstants.apiBaseUrl,
    deviceId: deviceId,
  );
});
```

### 2. Report Repository

Maps to the real backend endpoints under `/api/v1/reports`. The backend returns `{ data: [...], meta: {...} }` for list endpoints and flat JSON for single-resource endpoints.

```dart
// lib/features/feed/data/repositories/report_repository.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:crimereport/shared/data/api/api_client.dart';
import 'package:crimereport/features/feed/data/models/report.dart';

class ReportRepository {
  final ApiClient _api;
  ReportRepository(this._api);

  /// GET /api/v1/reports?lat=&lng=&radius=&limit=&offset=
  Future<List<Report>> getNearbyReports({
    required double lat,
    required double lng,
    int radius = 10000,
    int limit = 50,
    int offset = 0,
  }) async {
    final response = await _api.dio.get('/api/v1/reports', queryParameters: {
      'lat': lat,
      'lng': lng,
      'radius': radius,
      'limit': limit,
      'offset': offset,
    });
    final items = response.data['data'] as List<dynamic>;
    return items.map((json) => Report.fromJson(json as Map<String, dynamic>)).toList();
  }

  /// GET /api/v1/reports/:id
  Future<Report> getReport(String id) async {
    final response = await _api.dio.get('/api/v1/reports/$id');
    return Report.fromJson(response.data as Map<String, dynamic>);
  }

  /// POST /api/v1/reports
  Future<Report> createReport({
    required String type,
    required String description,
    required double lat,
    required double lng,
    String? address,
  }) async {
    final response = await _api.dio.post('/api/v1/reports', data: {
      'device_id': _api.dio.options.headers['X-Device-ID'],
      'type': type,
      'description': description,
      'lat': lat,
      'lng': lng,
      if (address != null) 'address': address,
    });
    return Report.fromJson(response.data as Map<String, dynamic>);
  }

  /// POST /api/v1/reports/:id/upvote — returns { upvoted: bool }
  Future<bool> toggleUpvote(String reportId) async {
    final response = await _api.dio.post('/api/v1/reports/$reportId/upvote', data: {
      'device_id': _api.dio.options.headers['X-Device-ID'],
    });
    return response.data['upvoted'] as bool;
  }
}

final reportRepositoryProvider = Provider<ReportRepository>((ref) {
  return ReportRepository(ref.watch(apiClientProvider));
});
```

### 3. Comment Repository

Matches the nested backend routes under `/api/v1/reports/:id/comments` and the standalone `/api/v1/comments/:id/flag`.

```dart
// lib/features/feed/data/repositories/comment_repository.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:crimereport/shared/data/api/api_client.dart';
import 'package:crimereport/features/feed/data/models/comment.dart';

class CommentRepository {
  final ApiClient _api;
  CommentRepository(this._api);

  /// GET /api/v1/reports/:reportId/comments?limit=&offset=
  Future<List<Comment>> getComments(String reportId, {int limit = 50, int offset = 0}) async {
    final response = await _api.dio.get(
      '/api/v1/reports/$reportId/comments',
      queryParameters: {'limit': limit, 'offset': offset},
    );
    final items = response.data['data'] as List<dynamic>;
    return items.map((json) => Comment.fromJson(json as Map<String, dynamic>)).toList();
  }

  /// POST /api/v1/reports/:reportId/comments
  Future<Comment> createComment(String reportId, String content) async {
    final response = await _api.dio.post('/api/v1/reports/$reportId/comments', data: {
      'device_id': _api.dio.options.headers['X-Device-ID'],
      'content': content,
    });
    return Comment.fromJson(response.data as Map<String, dynamic>);
  }

  /// POST /api/v1/comments/:id/flag
  Future<bool> flagComment(String commentId) async {
    final response = await _api.dio.post('/api/v1/comments/$commentId/flag', data: {
      'device_id': _api.dio.options.headers['X-Device-ID'],
    });
    return response.data['flagged'] as bool;
  }
}

final commentRepositoryProvider = Provider<CommentRepository>((ref) {
  return CommentRepository(ref.watch(apiClientProvider));
});
```

### 4. Update Feed Providers (replace MockDataService)

Modify `lib/features/feed/providers/feed_providers.dart` — swap `MockDataService` calls with `ReportRepository` / `CommentRepository`. The providers keep the same names so all existing UI code stays unchanged.

```dart
// lib/features/feed/providers/feed_providers.dart  (updated sections)

import 'package:crimereport/features/feed/data/repositories/report_repository.dart';
import 'package:crimereport/features/feed/data/repositories/comment_repository.dart';
import 'package:crimereport/features/map/providers/map_providers.dart';

/// Feed reports — fetched from API based on user location, filtered by active crime types.
final feedReportsProvider = FutureProvider.autoDispose<List<Report>>((ref) async {
  final activeFilters = ref.watch(crimeTypeFiltersProvider);
  final repo = ref.watch(reportRepositoryProvider);
  final position = ref.watch(userLocationProvider);

  if (position == null) return [];

  final reports = await repo.getNearbyReports(
    lat: position.latitude,
    lng: position.longitude,
  );

  if (activeFilters.length == ReportType.values.length) return reports;
  return reports.where((r) => activeFilters.contains(r.type)).toList();
});

/// Comments for a report — fetched from API.
final commentsProvider =
    FutureProvider.autoDispose.family<List<Comment>, String>((ref, reportId) {
  final repo = ref.watch(commentRepositoryProvider);
  return repo.getComments(reportId);
});

/// Toggle upvote via API, then refresh feed.
Future<void> toggleUpvote(WidgetRef ref, String reportId) async {
  final repo = ref.read(reportRepositoryProvider);
  final upvoted = await repo.toggleUpvote(reportId);

  final notifier = ref.read(upvotedReportsProvider.notifier);
  final current = notifier.state;
  if (upvoted) {
    notifier.state = {...current, reportId};
  } else {
    notifier.state = {...current}..remove(reportId);
  }

  ref.invalidate(feedReportsProvider);
}
```

### 5. Update Map Providers (replace MockDataService)

Modify `lib/features/map/providers/map_providers.dart` — switch `mapReportsProvider` from synchronous mock data to an async API fetch.

```dart
// lib/features/map/providers/map_providers.dart  (updated section)

import 'package:crimereport/features/feed/data/repositories/report_repository.dart';

/// Map reports — fetched from API based on user location, filtered by crime type.
final mapReportsProvider = FutureProvider<List<Report>>((ref) async {
  final activeFilters = ref.watch(crimeTypeFiltersProvider);
  final repo = ref.watch(reportRepositoryProvider);
  final position = ref.watch(userLocationProvider);

  if (position == null) return [];

  final allReports = await repo.getNearbyReports(
    lat: position.latitude,
    lng: position.longitude,
    radius: AppConstants.defaultRadiusMeters,
  );

  if (activeFilters.length == ReportType.values.length) return allReports;
  return allReports.where((r) => activeFilters.contains(r.type)).toList();
});
```

> **Note:** `mapReportsProvider` changes from `Provider<List<Report>>` (sync) to `FutureProvider<List<Report>>` (async). The map screen will need to handle `AsyncValue` — use `.when(data:, loading:, error:)`.

### 6. Error Handling Widget

A reusable widget for wrapping `AsyncValue` consumers with consistent loading/error UX. Displays shimmer placeholders during loading and a retry button on errors.

```dart
// lib/shared/widgets/api_error_handler.dart

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:crimereport/shared/data/api/api_client.dart';

class ApiErrorView extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;

  const ApiErrorView({super.key, required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, size: 48, color: Colors.grey[600]),
            const SizedBox(height: 16),
            Text(
              _messageFor(error),
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[400], fontSize: 14),
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  static String _messageFor(Object error) {
    if (error is DioException) {
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
          return 'Connection timed out. Check your internet.';
        case DioExceptionType.receiveTimeout:
          return 'Server took too long to respond.';
        case DioExceptionType.connectionError:
          return 'No internet connection.';
        default:
          final msg = error.response?.data;
          if (msg is Map && msg['error'] != null) return msg['error'].toString();
          return 'Something went wrong.';
      }
    }
    if (error is RateLimitException) {
      return 'Too many requests. Please wait a moment.';
    }
    return 'An unexpected error occurred.';
  }
}
```

### 7. Extend ReportStatus Enum

The backend uses statuses `pending`, `uploading`, `processing`, `active`, `failed`, `removed` for the media upload lifecycle. The current Flutter `ReportStatus` enum only has `pending`, `verified`, `flagged`, `removed`. Update it to match.

```dart
// lib/core/constants/enums.dart  (updated ReportStatus)

enum ReportStatus {
  pending('Pending'),
  uploading('Uploading'),
  processing('Processing'),
  active('Active'),
  failed('Failed'),
  flagged('Flagged'),
  removed('Removed');

  const ReportStatus(this.displayName);
  final String displayName;
}
```

### 8. Device ID Header via Interceptor

The `anonymousIdProvider` is async (reads from SharedPreferences). On first app launch, the device ID won't be ready immediately. Add logic so `ApiClient` updates its header once the ID resolves.

```dart
// In api_client.dart — alternative: expose a method to set device ID later

void updateDeviceId(String deviceId) {
  dio.options.headers['X-Device-ID'] = deviceId;
}
```

Then in `apiClientProvider`, listen for changes:

```dart
final apiClientProvider = Provider<ApiClient>((ref) {
  final client = ApiClient(baseUrl: AppConstants.apiBaseUrl, deviceId: '');
  ref.listen<AsyncValue<String>>(anonymousIdProvider, (_, next) {
    final id = next.valueOrNull;
    if (id != null) client.updateDeviceId(id);
  }, fireImmediately: true);
  return client;
});
```

## Testing Plan

- **Unit tests** for `ReportRepository` and `CommentRepository` — mock dio adapter, verify correct URL/params/body for each endpoint, verify `Report.fromJson` / `Comment.fromJson` parsing against real API response shapes.
- **Unit tests** for `ApiClient` — verify interceptor transforms 429 into `RateLimitException`.
- **Provider tests** — verify `feedReportsProvider` calls repository and applies crime-type filters.
- **Widget tests** — verify `ApiErrorView` shows correct messages for timeout, connection error, rate limit.
- **Integration test** — full flow: app launches → feed loads from API → upvote sends POST → feed refreshes.

## Notes

- **What gets replaced:** `MockDataService` is no longer called anywhere. The class and `SampleData` can remain for reference/testing but are disconnected from the provider graph.
- **API prefix:** All backend routes live under `/api/v1` (see `app.ts` line 24). Reports at `/api/v1/reports`, comments nested at `/api/v1/reports/:id/comments`, flag at `/api/v1/comments/:id/flag`.
- **Response shapes:** List endpoints return `{ data: [...], meta: {...} }`. Single-resource endpoints (GET `/:id`, POST `/`) return the object directly.
- **`mapReportsProvider` becomes async:** This is a breaking change for `MapScreen` and `MapMarkerManager` which currently consume a synchronous `Provider<List<Report>>`. They must be updated to handle `AsyncValue`.
- **`locationFeedReportsProvider`** also needs to switch from `MockDataService.instance.getNearbyReports(...)` to `reportRepositoryProvider`. Since it's a synchronous `Provider.family`, it will need to become a `FutureProvider.family`.
- **No new dependencies needed** — `dio: ^5.4.0` is already in pubspec.yaml.

## Files

| # | Path | Action |
|---|------|--------|
| 1 | `lib/shared/data/api/api_client.dart` | Create |
| 2 | `lib/features/feed/data/repositories/report_repository.dart` | Create |
| 3 | `lib/features/feed/data/repositories/comment_repository.dart` | Create |
| 4 | `lib/shared/widgets/api_error_handler.dart` | Create |
| 5 | `lib/features/feed/providers/feed_providers.dart` | Modify — replace MockDataService with repositories |
| 6 | `lib/features/map/providers/map_providers.dart` | Modify — replace MockDataService, make async |
| 7 | `lib/core/constants/enums.dart` | Modify — extend ReportStatus |
| 8 | `lib/features/map/presentation/map_screen.dart` | Modify — handle AsyncValue from mapReportsProvider |
| 9 | `lib/features/map/presentation/map_marker_manager.dart` | Modify — handle AsyncValue |
| 10 | `lib/features/map/presentation/location_feed_screen.dart` | Modify — use async locationFeedReportsProvider |
