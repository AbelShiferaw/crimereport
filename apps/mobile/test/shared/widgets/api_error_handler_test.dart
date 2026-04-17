import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crimereport/shared/data/api/api_client.dart';
import 'package:crimereport/shared/widgets/api_error_handler.dart';

void main() {
  Widget buildTestWidget(Object error, {VoidCallback? onRetry}) {
    return MaterialApp(
      home: Scaffold(
        body: ApiErrorView(error: error, onRetry: onRetry),
      ),
    );
  }

  group('ApiErrorView', () {
    group('generic errors', () {
      testWidgets('shows fallback message for unknown errors',
          (tester) async {
        await tester.pumpWidget(buildTestWidget(Exception('oops')));

        expect(find.text('Something went wrong. Please try again.'),
            findsOneWidget);
        expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
      });

      testWidgets('shows fallback message for string errors',
          (tester) async {
        await tester.pumpWidget(buildTestWidget('string error'));

        expect(find.text('Something went wrong. Please try again.'),
            findsOneWidget);
      });
    });

    group('RateLimitException', () {
      testWidgets('shows rate limit message for direct RateLimitException',
          (tester) async {
        await tester.pumpWidget(
          buildTestWidget(const RateLimitException()),
        );

        expect(
          find.text(
              'Too many requests. Please wait a moment and try again.'),
          findsOneWidget,
        );
        expect(find.byIcon(Icons.timer_outlined), findsOneWidget);
      });

      testWidgets(
          'shows rate limit message when DioException wraps RateLimitException',
          (tester) async {
        final dioError = DioException(
          requestOptions: RequestOptions(path: '/test'),
          error: const RateLimitException(),
          type: DioExceptionType.badResponse,
        );

        await tester.pumpWidget(buildTestWidget(dioError));

        expect(
          find.text(
              'Too many requests. Please wait a moment and try again.'),
          findsOneWidget,
        );
        expect(find.byIcon(Icons.timer_outlined), findsOneWidget);
      });
    });

    group('DioException types', () {
      testWidgets('shows timeout message for connectionTimeout',
          (tester) async {
        final error = DioException(
          requestOptions: RequestOptions(path: '/test'),
          type: DioExceptionType.connectionTimeout,
        );

        await tester.pumpWidget(buildTestWidget(error));

        expect(
          find.text(
              'Connection timed out. Check your network and try again.'),
          findsOneWidget,
        );
        expect(find.byIcon(Icons.hourglass_empty_rounded), findsOneWidget);
      });

      testWidgets('shows timeout message for sendTimeout', (tester) async {
        final error = DioException(
          requestOptions: RequestOptions(path: '/test'),
          type: DioExceptionType.sendTimeout,
        );

        await tester.pumpWidget(buildTestWidget(error));

        expect(
          find.text(
              'Connection timed out. Check your network and try again.'),
          findsOneWidget,
        );
      });

      testWidgets('shows timeout message for receiveTimeout',
          (tester) async {
        final error = DioException(
          requestOptions: RequestOptions(path: '/test'),
          type: DioExceptionType.receiveTimeout,
        );

        await tester.pumpWidget(buildTestWidget(error));

        expect(
          find.text(
              'Connection timed out. Check your network and try again.'),
          findsOneWidget,
        );
      });

      testWidgets('shows connection error message', (tester) async {
        final error = DioException(
          requestOptions: RequestOptions(path: '/test'),
          type: DioExceptionType.connectionError,
        );

        await tester.pumpWidget(buildTestWidget(error));

        expect(
          find.text(
              'Unable to connect. Please check your internet connection.'),
          findsOneWidget,
        );
        expect(find.byIcon(Icons.wifi_off_rounded), findsOneWidget);
      });

      testWidgets('shows server error for 5xx status codes',
          (tester) async {
        final error = DioException(
          requestOptions: RequestOptions(path: '/test'),
          type: DioExceptionType.badResponse,
          response: Response(
            requestOptions: RequestOptions(path: '/test'),
            statusCode: 500,
          ),
        );

        await tester.pumpWidget(buildTestWidget(error));

        expect(
          find.text('Server error. Please try again later.'),
          findsOneWidget,
        );
        expect(find.byIcon(Icons.cloud_off_rounded), findsOneWidget);
      });

      testWidgets('shows server error for 503', (tester) async {
        final error = DioException(
          requestOptions: RequestOptions(path: '/test'),
          type: DioExceptionType.badResponse,
          response: Response(
            requestOptions: RequestOptions(path: '/test'),
            statusCode: 503,
          ),
        );

        await tester.pumpWidget(buildTestWidget(error));

        expect(
          find.text('Server error. Please try again later.'),
          findsOneWidget,
        );
      });

      testWidgets('shows not found message for 404', (tester) async {
        final error = DioException(
          requestOptions: RequestOptions(path: '/test'),
          type: DioExceptionType.badResponse,
          response: Response(
            requestOptions: RequestOptions(path: '/test'),
            statusCode: 404,
          ),
        );

        await tester.pumpWidget(buildTestWidget(error));

        expect(
          find.text('The requested resource was not found.'),
          findsOneWidget,
        );
        expect(find.byIcon(Icons.search_off_rounded), findsOneWidget);
      });

      testWidgets('shows status code for other 4xx errors',
          (tester) async {
        final error = DioException(
          requestOptions: RequestOptions(path: '/test'),
          type: DioExceptionType.badResponse,
          response: Response(
            requestOptions: RequestOptions(path: '/test'),
            statusCode: 422,
          ),
        );

        await tester.pumpWidget(buildTestWidget(error));

        expect(
          find.text('Request failed (status 422).'),
          findsOneWidget,
        );
      });

      testWidgets('shows generic network error for unknown DioException type',
          (tester) async {
        final error = DioException(
          requestOptions: RequestOptions(path: '/test'),
          type: DioExceptionType.cancel,
        );

        await tester.pumpWidget(buildTestWidget(error));

        expect(
          find.text('An unexpected network error occurred.'),
          findsOneWidget,
        );
      });
    });

    group('retry button', () {
      testWidgets('shows retry button when onRetry is provided',
          (tester) async {
        await tester.pumpWidget(
          buildTestWidget(Exception('fail'), onRetry: () {}),
        );

        expect(find.text('Retry'), findsOneWidget);
        expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);
      });

      testWidgets('hides retry button when onRetry is null',
          (tester) async {
        await tester.pumpWidget(buildTestWidget(Exception('fail')));

        expect(find.text('Retry'), findsNothing);
      });

      testWidgets('calls onRetry when retry button is tapped',
          (tester) async {
        var retryCount = 0;

        await tester.pumpWidget(
          buildTestWidget(
            Exception('fail'),
            onRetry: () => retryCount++,
          ),
        );

        await tester.tap(find.text('Retry'));
        expect(retryCount, 1);
      });
    });
  });
}
