class AppConstants {
  // API Configuration
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:3000',
  );

  static const String wsBaseUrl = String.fromEnvironment(
    'WS_BASE_URL',
    defaultValue: 'ws://localhost:3000',
  );

  // Map Configuration
  static const String mapboxToken = String.fromEnvironment(
    'MAPBOX_TOKEN',
    defaultValue: '',
  );

  // Default Values
  static const double defaultLatitude = 37.7749; // San Francisco
  static const double defaultLongitude = -122.4194;
  static const int defaultRadiusMeters = 10000; // 10km

  // Rate Limits
  static const int maxReportsPerDay = 10;
  static const int maxCommentsPerHour = 30;

  // Media
  static const int maxVideoSizeMB = 100;
  static const int maxImageSizeMB = 10;
  static const int maxVideoDurationSeconds = 60;

  // Cache
  static const int nearbyReportsCacheTTL = 60; // seconds
}
