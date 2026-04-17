import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crimereport/shared/data/api/api_client.dart';

/// Mock adapter that returns a fixed status code and optional headers.
class _MockHttpClientAdapter implements HttpClientAdapter {
  final int statusCode;
  final String body;
  final Map<String, List<String>> headers;

  _MockHttpClientAdapter({
    required this.statusCode,
    this.body = '{}',
    this.headers = const {},
  });

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(body, statusCode, headers: headers);
  }

  @override
  void close({bool force = false}) {}
}

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
      final client = ApiClient(baseUrl: 'http://test.example.com');
      client.dio.httpClientAdapter = _MockHttpClientAdapter(
        statusCode: 429,
        body: '{"error": "Too Many Requests"}',
        headers: {'retry-after': ['60']},
      );

      try {
        await client.get('/test');
        fail('Expected DioException to be thrown');
      } on DioException catch (e) {
        expect(e.error, isA<RateLimitException>());
        final rateError = e.error as RateLimitException;
        expect(rateError.retryAfterSeconds, 60);
      }
    });

    test('handles missing retry-after header', () async {
      final client = ApiClient(baseUrl: 'http://test.example.com');
      client.dio.httpClientAdapter = _MockHttpClientAdapter(
        statusCode: 429,
        body: '{"error": "Too Many Requests"}',
      );

      try {
        await client.get('/test');
        fail('Expected DioException to be thrown');
      } on DioException catch (e) {
        expect(e.error, isA<RateLimitException>());
        final rateError = e.error as RateLimitException;
        expect(rateError.retryAfterSeconds, isNull);
      }
    });

    test('does not convert non-429 errors', () async {
      final client = ApiClient(baseUrl: 'http://test.example.com');
      client.dio.httpClientAdapter = _MockHttpClientAdapter(
        statusCode: 500,
        body: '{"error": "Internal Server Error"}',
      );

      try {
        await client.get('/test');
        fail('Expected DioException to be thrown');
      } on DioException catch (e) {
        expect(e.error, isNot(isA<RateLimitException>()));
        expect(e.response?.statusCode, 500);
      }
    });

    test('handles non-numeric retry-after header', () async {
      final client = ApiClient(baseUrl: 'http://test.example.com');
      client.dio.httpClientAdapter = _MockHttpClientAdapter(
        statusCode: 429,
        body: '{"error": "Too Many Requests"}',
        headers: {'retry-after': ['not-a-number']},
      );

      try {
        await client.get('/test');
        fail('Expected DioException to be thrown');
      } on DioException catch (e) {
        expect(e.error, isA<RateLimitException>());
        final rateError = e.error as RateLimitException;
        expect(rateError.retryAfterSeconds, isNull);
      }
    });

    test('RateLimitException with retryAfterSeconds of 0', () {
      const e = RateLimitException(retryAfterSeconds: 0);
      expect(e.retryAfterSeconds, 0);
    });
  });
}
