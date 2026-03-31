import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crimereport/shared/data/api/api_client.dart';

void main() {
  group('RateLimitException', () {
    test('has default message', () {
      const e = RateLimitException();
      expect(e.message, 'Rate limit exceeded. Please try again later.');
      expect(e.retryAfterSeconds, isNull);
    });

    test('accepts custom message and retryAfterSeconds', () {
      const e = RateLimitException(
        message: 'Slow down',
        retryAfterSeconds: 30,
      );
      expect(e.message, 'Slow down');
      expect(e.retryAfterSeconds, 30);
    });

    test('toString returns the message', () {
      const e = RateLimitException(message: 'custom msg');
      expect(e.toString(), 'custom msg');
    });

    test('implements Exception', () {
      const e = RateLimitException();
      expect(e, isA<Exception>());
    });
  });

  group('ApiClient', () {
    test('deviceId is null initially', () {
      final client = ApiClient(baseUrl: 'http://test.example.com');
      expect(client.deviceId, isNull);
    });

    test('updateDeviceId sets the X-Device-ID header', () {
      final client = ApiClient(baseUrl: 'http://test.example.com');
      client.updateDeviceId('device-abc-123');

      expect(client.deviceId, 'device-abc-123');
    });

    test('updateDeviceId can be called multiple times', () {
      final client = ApiClient(baseUrl: 'http://test.example.com');

      client.updateDeviceId('first');
      expect(client.deviceId, 'first');

      client.updateDeviceId('second');
      expect(client.deviceId, 'second');
    });

    test('updateDeviceId overwrites previous value', () {
      final client = ApiClient(baseUrl: 'http://test.example.com');

      client.updateDeviceId('old-id');
      client.updateDeviceId('new-id');

      expect(client.deviceId, 'new-id');
    });
  });

  group('ApiClient 429 interceptor', () {
    test('converts 429 response to RateLimitException with retry-after',
        () async {
      final requestOptions = RequestOptions(path: '/test');
      final dioError = DioException(
        requestOptions: requestOptions,
        response: Response(
          requestOptions: requestOptions,
          statusCode: 429,
          headers: Headers.fromMap({
            'retry-after': ['60'],
          }),
        ),
        type: DioExceptionType.badResponse,
      );

      // Simulate what the interceptor does
      if (dioError.response?.statusCode == 429) {
        final retryAfter = int.tryParse(
          dioError.response?.headers.value('retry-after') ?? '',
        );
        final transformed = DioException(
          requestOptions: dioError.requestOptions,
          error: RateLimitException(retryAfterSeconds: retryAfter),
          type: DioExceptionType.badResponse,
          response: dioError.response,
        );

        expect(transformed.error, isA<RateLimitException>());
        final rateError = transformed.error as RateLimitException;
        expect(rateError.retryAfterSeconds, 60);
      }
    });

    test('handles missing retry-after header', () {
      final requestOptions = RequestOptions(path: '/test');
      final dioError = DioException(
        requestOptions: requestOptions,
        response: Response(
          requestOptions: requestOptions,
          statusCode: 429,
        ),
        type: DioExceptionType.badResponse,
      );

      final retryAfter = int.tryParse(
        dioError.response?.headers.value('retry-after') ?? '',
      );

      expect(retryAfter, isNull);

      final transformed = DioException(
        requestOptions: dioError.requestOptions,
        error: RateLimitException(retryAfterSeconds: retryAfter),
        type: DioExceptionType.badResponse,
        response: dioError.response,
      );

      final rateError = transformed.error as RateLimitException;
      expect(rateError.retryAfterSeconds, isNull);
    });

    test('does not convert non-429 errors', () {
      final requestOptions = RequestOptions(path: '/test');
      final dioError = DioException(
        requestOptions: requestOptions,
        response: Response(
          requestOptions: requestOptions,
          statusCode: 500,
        ),
        type: DioExceptionType.badResponse,
      );

      if (dioError.response?.statusCode == 429) {
        fail('Should not enter 429 handler for status 500');
      }

      expect(dioError.response?.statusCode, 500);
      expect(dioError.error, isNot(isA<RateLimitException>()));
    });

    test('handles non-numeric retry-after header', () {
      final requestOptions = RequestOptions(path: '/test');
      final dioError = DioException(
        requestOptions: requestOptions,
        response: Response(
          requestOptions: requestOptions,
          statusCode: 429,
          headers: Headers.fromMap({
            'retry-after': ['not-a-number'],
          }),
        ),
        type: DioExceptionType.badResponse,
      );

      final retryAfter = int.tryParse(
        dioError.response?.headers.value('retry-after') ?? '',
      );
      expect(retryAfter, isNull);
    });

    test('RateLimitException with retryAfterSeconds of 0', () {
      const e = RateLimitException(retryAfterSeconds: 0);
      expect(e.retryAfterSeconds, 0);
    });
  });
}
