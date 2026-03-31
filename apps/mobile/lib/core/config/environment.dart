/// Environment configuration for dev, staging, and production builds.
///
/// The active environment is selected at compile time via
/// `--dart-define=ENV=prod` (or `staging`). Defaults to `dev`.
enum Environment { dev, staging, prod }

class AppConfig {
  AppConfig._();

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

  static String get cdnBaseUrl {
    switch (environment) {
      case Environment.prod:
        return 'https://cdn.reportcrime.app';
      case Environment.staging:
        return 'https://staging-cdn.reportcrime.app';
      case Environment.dev:
        return 'http://localhost:3000';
    }
  }

  static bool get isProduction => environment == Environment.prod;
  static bool get isStaging => environment == Environment.staging;
  static bool get isDevelopment => environment == Environment.dev;
}
