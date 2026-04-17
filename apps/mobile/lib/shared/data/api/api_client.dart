import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:crimereport/core/constants/app_constants.dart';
import 'package:crimereport/features/settings/providers/settings_providers.dart';

/// Thrown when the server returns HTTP 429 (Too Many Requests).
class RateLimitException implements Exception {
  final String message;
  final int? retryAfterSeconds;

  const RateLimitException({
    this.message = 'Rate limit exceeded. Please try again later.',
    this.retryAfterSeconds,
  });

  @override
  String toString() => message;
}

/// Centralized Dio HTTP client for all REST API calls.
class ApiClient {
  late final Dio _dio;

  ApiClient({String? baseUrl}) {
    _dio = Dio(
      BaseOptions(
        baseUrl: baseUrl ?? AppConstants.apiBaseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 15),
        headers: {'Content-Type': 'application/json'},
      ),
    );

    _dio.interceptors.add(
      InterceptorsWrapper(
        onError: (error, handler) {
          if (error.response?.statusCode == 429) {
            final retryAfter = int.tryParse(
              error.response?.headers.value('retry-after') ?? '',
            );
            return handler.reject(
              DioException(
                requestOptions: error.requestOptions,
                error: RateLimitException(retryAfterSeconds: retryAfter),
                type: DioExceptionType.badResponse,
                response: error.response,
              ),
            );
          }
          return handler.next(error);
        },
      ),
    );

    if (kDebugMode) {
      _dio.interceptors.add(
        LogInterceptor(
          requestBody: true,
          responseBody: true,
          logPrint: (obj) => debugPrint(obj.toString()),
        ),
      );
    }
  }

  /// The underlying Dio instance, exposed for test-only access.
  @visibleForTesting
  Dio get dio => _dio;

  /// Update the X-Device-ID header used for anonymous identification.
  void updateDeviceId(String deviceId) {
    _dio.options.headers['X-Device-ID'] = deviceId;
  }

  /// The device ID currently set on outgoing requests.
  String? get deviceId => _dio.options.headers['X-Device-ID'] as String?;

  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) =>
      _dio.get<T>(path, queryParameters: queryParameters);

  Future<Response<T>> post<T>(
    String path, {
    dynamic data,
  }) =>
      _dio.post<T>(path, data: data);

  Future<Response<T>> put<T>(
    String path, {
    dynamic data,
  }) =>
      _dio.put<T>(path, data: data);

  Future<Response<T>> delete<T>(String path) => _dio.delete<T>(path);
}

/// Global [ApiClient] provider.
///
/// Listens to [anonymousIdProvider] and sets the X-Device-ID header once
/// the persisted anonymous ID resolves.
final apiClientProvider = Provider<ApiClient>((ref) {
  final client = ApiClient();

  final asyncId = ref.watch(anonymousIdProvider);
  asyncId.whenData((deviceId) {
    client.updateDeviceId(deviceId);
  });

  return client;
});
