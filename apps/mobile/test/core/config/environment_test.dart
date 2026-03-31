import 'package:flutter_test/flutter_test.dart';

import 'package:crimereport/core/config/environment.dart';

void main() {
  group('AppConfig', () {
    // Note: String.fromEnvironment is resolved at compile time, so
    // in tests (without --dart-define) it always defaults to 'dev'.
    test('defaults to dev environment', () {
      expect(AppConfig.environment, Environment.dev);
    });

    test('isDevelopment is true by default', () {
      expect(AppConfig.isDevelopment, isTrue);
    });

    test('isProduction is false by default', () {
      expect(AppConfig.isProduction, isFalse);
    });

    test('isStaging is false by default', () {
      expect(AppConfig.isStaging, isFalse);
    });

    test('dev apiBaseUrl points to localhost', () {
      expect(AppConfig.apiBaseUrl, 'http://localhost:3000');
    });

    test('dev wsBaseUrl points to localhost', () {
      expect(AppConfig.wsBaseUrl, 'ws://localhost:3000');
    });

    test('dev cdnBaseUrl points to localhost', () {
      expect(AppConfig.cdnBaseUrl, 'http://localhost:3000');
    });
  });

  group('Environment enum', () {
    test('has exactly three values', () {
      expect(Environment.values.length, 3);
    });

    test('contains dev, staging, and prod', () {
      expect(Environment.values, contains(Environment.dev));
      expect(Environment.values, contains(Environment.staging));
      expect(Environment.values, contains(Environment.prod));
    });
  });
}
