# Milestone 25: Flutter ↔ REST API

## Goal
Connect the Flutter app to the live backend REST API, replacing mock data with real API calls.

## Dependencies
Requires **Milestone 13** (Flutter app complete) and **Milestone 20-22** (API endpoints working).

## Implementation

### 1. API Client Setup
```dart
// lib/shared/data/api/api_client.dart

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ApiClient {
  late final Dio _dio;
  
  ApiClient({required String baseUrl, required String deviceId}) {
    _dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: Duration(seconds: 10),
      receiveTimeout: Duration(seconds: 30),
      headers: {
        'Content-Type': 'application/json',
        'X-Device-ID': deviceId,
      },
    ));
    
    // Request/response logging
    _dio.interceptors.add(LogInterceptor(
      requestBody: true,
      responseBody: true,
    ));
    
    // Error handling interceptor
    _dio.interceptors.add(InterceptorsWrapper(
      onError: (error, handler) {
        // Transform errors
        if (error.response?.statusCode == 429) {
          throw RateLimitException();
        }
        handler.next(error);
      },
    ));
  }
  
  Future<T> get<T>(String path, {Map<String, dynamic>? queryParams}) async {
    final response = await _dio.get(path, queryParameters: queryParams);
    return response.data['data'] as T;
  }
  
  Future<T> post<T>(String path, {Map<String, dynamic>? data}) async {
    final response = await _dio.post(path, data: data);
    return response.data['data'] as T;
  }
  
  Future<void> delete(String path) async {
    await _dio.delete(path);
  }
}

// Provider
final apiClientProvider = Provider<ApiClient>((ref) {
  final deviceId = ref.watch(deviceIdProvider).value ?? '';
  return ApiClient(
    baseUrl: AppConstants.apiBaseUrl,
    deviceId: deviceId,
  );
});
```

### 2. Report Repository (API Implementation)
```dart
// lib/features/feed/data/repositories/report_repository.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';

class ReportRepository {
  final ApiClient _api;
  
  ReportRepository(this._api);
  
  Future<List<Report>> getNearbyReports(double lat, double lng, {int radius = 10000}) async {
    final data = await _api.get<List<dynamic>>(
      '/api/v1/reports/nearby',
      queryParams: {'lat': lat, 'lng': lng, 'radius': radius},
    );
    return data.map((json) => Report.fromJson(json)).toList();
  }
  
  Future<List<Report>> getReportsAtLocation(double lat, double lng) async {
    final data = await _api.get<List<dynamic>>(
      '/api/v1/reports/location',
      queryParams: {'lat': lat, 'lng': lng},
    );
    return data.map((json) => Report.fromJson(json)).toList();
  }
  
  Future<Report> getReport(String id) async {
    final data = await _api.get<Map<String, dynamic>>('/api/v1/reports/$id');
    return Report.fromJson(data);
  }
  
  Future<Report> createReport(CreateReportRequest request) async {
    final data = await _api.post<Map<String, dynamic>>(
      '/api/v1/reports',
      data: request.toJson(),
    );
    return Report.fromJson(data);
  }
  
  Future<UpvoteResult> upvoteReport(String id) async {
    final data = await _api.post<Map<String, dynamic>>('/api/v1/reports/$id/upvote');
    return UpvoteResult.fromJson(data);
  }
  
  Future<void> flagReport(String id, String reason) async {
    await _api.post('/api/v1/reports/$id/flag', data: {'reason': reason});
  }
}

final reportRepositoryProvider = Provider<ReportRepository>((ref) {
  return ReportRepository(ref.watch(apiClientProvider));
});
```

### 3. Update Providers to Use API
```dart
// lib/shared/providers/report_providers.dart

final nearbyReportsProvider = FutureProvider.family<List<Report>, LatLng>((ref, location) async {
  final repo = ref.watch(reportRepositoryProvider);
  return repo.getNearbyReports(location.latitude, location.longitude);
});

final reportProvider = FutureProvider.family<Report, String>((ref, id) async {
  final repo = ref.watch(reportRepositoryProvider);
  return repo.getReport(id);
});

// Mutation providers
final upvoteReportProvider = Provider((ref) {
  return (String reportId) async {
    final repo = ref.read(reportRepositoryProvider);
    final result = await repo.upvoteReport(reportId);
    
    // Invalidate to refresh
    ref.invalidate(nearbyReportsProvider);
    
    return result;
  };
});
```

### 4. Comment Repository
```dart
// lib/features/feed/data/repositories/comment_repository.dart

class CommentRepository {
  final ApiClient _api;
  
  CommentRepository(this._api);
  
  Future<List<Comment>> getComments(String reportId) async {
    final data = await _api.get<List<dynamic>>('/api/v1/comments/report/$reportId');
    return data.map((json) => Comment.fromJson(json)).toList();
  }
  
  Future<Comment> createComment(String reportId, String content) async {
    final data = await _api.post<Map<String, dynamic>>(
      '/api/v1/comments',
      data: {'report_id': reportId, 'content': content},
    );
    return Comment.fromJson(data);
  }
  
  Future<UpvoteResult> upvoteComment(String id) async {
    final data = await _api.post<Map<String, dynamic>>('/api/v1/comments/$id/upvote');
    return UpvoteResult.fromJson(data);
  }
  
  Future<void> deleteComment(String id) async {
    await _api.delete('/api/v1/comments/$id');
  }
}
```

### 5. Media Upload Service
```dart
// lib/features/submit/data/services/upload_service.dart

import 'package:dio/dio.dart';

class UploadService {
  final ApiClient _api;
  
  UploadService(this._api);
  
  Future<UploadResult> uploadMedia(String filePath, {
    void Function(int, int)? onProgress,
  }) async {
    final file = File(filePath);
    final filename = path.basename(filePath);
    final contentType = _getContentType(filename);
    final fileSize = await file.length();
    
    // 1. Get presigned URL
    final presigned = await _api.post<Map<String, dynamic>>(
      '/api/v1/uploads/presigned-url',
      data: {
        'filename': filename,
        'contentType': contentType,
        'fileSize': fileSize,
      },
    );
    
    // 2. Upload to S3
    final uploadDio = Dio();
    await uploadDio.put(
      presigned['uploadUrl'],
      data: file.openRead(),
      options: Options(
        headers: {
          'Content-Type': contentType,
          'Content-Length': fileSize,
        },
      ),
      onSendProgress: onProgress,
    );
    
    return UploadResult(
      uploadId: presigned['uploadId'],
      key: presigned['key'],
    );
  }
  
  Future<Media> completeUpload(String uploadId, String reportId) async {
    final data = await _api.post<Map<String, dynamic>>(
      '/api/v1/uploads/complete',
      data: {'uploadId': uploadId, 'reportId': reportId},
    );
    return Media.fromJson(data);
  }
  
  String _getContentType(String filename) {
    final ext = path.extension(filename).toLowerCase();
    switch (ext) {
      case '.mp4': return 'video/mp4';
      case '.mov': return 'video/quicktime';
      case '.jpg':
      case '.jpeg': return 'image/jpeg';
      case '.png': return 'image/png';
      default: throw Exception('Unsupported file type');
    }
  }
}
```

### 6. Error Handling UI
```dart
// lib/shared/widgets/api_error_handler.dart

class ApiErrorHandler extends ConsumerWidget {
  final AsyncValue<dynamic> asyncValue;
  final Widget Function(dynamic data) builder;
  final VoidCallback onRetry;
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return asyncValue.when(
      data: builder,
      loading: () => Center(child: CircularProgressIndicator()),
      error: (error, stack) => ErrorView(
        message: _getErrorMessage(error),
        onRetry: onRetry,
      ),
    );
  }
  
  String _getErrorMessage(Object error) {
    if (error is DioException) {
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
          return 'Connection timed out. Check your internet.';
        case DioExceptionType.receiveTimeout:
          return 'Server took too long to respond.';
        default:
          return error.response?.data?['error']?['message'] ?? 'Something went wrong';
      }
    }
    if (error is RateLimitException) {
      return 'Too many requests. Please wait a moment.';
    }
    return 'An unexpected error occurred';
  }
}
```

### 7. Update Feed Screen
```dart
// lib/features/feed/presentation/feed_screen.dart (updated)

class FeedScreen extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = ref.watch(userLocationProvider);
    
    return location.when(
      data: (pos) {
        final reports = ref.watch(nearbyReportsProvider(LatLng(pos.latitude, pos.longitude)));
        
        return ApiErrorHandler(
          asyncValue: reports,
          onRetry: () => ref.invalidate(nearbyReportsProvider),
          builder: (data) => FeedVideoList(reports: data),
        );
      },
      loading: () => FeedLoadingSkeleton(),
      error: (e, _) => ErrorView(message: 'Could not get location'),
    );
  }
}
```

## Configuration
```dart
// lib/core/constants/app_constants.dart

class AppConstants {
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://api.reportcrime.app',
  );
}
```

## Deliverable Checklist
- [ ] ApiClient configured with device ID header
- [ ] ReportRepository fetches from real API
- [ ] Feed shows real nearby reports
- [ ] Map shows real crime markers
- [ ] Upvote sends to API and updates UI
- [ ] CommentRepository fetches/creates comments
- [ ] Media upload with progress indicator
- [ ] Error states handled gracefully
- [ ] Loading states show skeletons
- [ ] Pull-to-refresh works
- [ ] Rate limit errors shown to user

## Files (8 total)
1. `lib/shared/data/api/api_client.dart` - Create
2. `lib/features/feed/data/repositories/report_repository.dart` - Create
3. `lib/features/feed/data/repositories/comment_repository.dart` - Create
4. `lib/features/submit/data/services/upload_service.dart` - Create
5. `lib/shared/providers/report_providers.dart` - Update
6. `lib/shared/widgets/api_error_handler.dart` - Create
7. `lib/features/feed/presentation/feed_screen.dart` - Update
8. `lib/core/constants/app_constants.dart` - Update
