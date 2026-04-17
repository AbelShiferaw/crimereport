import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppConstants {
  // API Configuration — reads from .env at runtime, falls back to --dart-define,
  // then to localhost for local development.
  static String get apiBaseUrl =>
      dotenv.env['API_BASE_URL'] ??
      const String.fromEnvironment('API_BASE_URL',
          defaultValue: 'http://localhost:3000');

  static String get wsBaseUrl =>
      dotenv.env['WS_BASE_URL'] ??
      const String.fromEnvironment('WS_BASE_URL',
          defaultValue: 'ws://localhost:3000');

  // Map Configuration
  static String get mapboxToken =>
      dotenv.env['MAPBOX_ACCESS_TOKEN'] ??
      const String.fromEnvironment('MAPBOX_TOKEN', defaultValue: '');

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

  // Video Feed
  static const int videoPreloadRange = 1; // Preload ±1 videos
  static const int maxCachedVideoControllers = 5;
  static const Duration videoLoadTimeout = Duration(seconds: 15);

  // Feed Overlay UI
  static const double feedNavBarHeight = 64.0;
  static const double feedNavBarMargin = 4.0; // Reduced to sit lower
  static const double feedActionButtonSize = 48.0;
  static const double feedActionButtonSpacing = 20.0;
  static const double feedInfoBarRightMargin = 80.0; // Clear action buttons

  // Animations
  static const Duration standardTransition = Duration(milliseconds: 200);
  static const Duration fastTransition = Duration(milliseconds: 100);
  static const Duration heartAnimationDuration = Duration(milliseconds: 800);
  static const Duration overlayFadeDuration = Duration(milliseconds: 150);
  static const Duration navBarAnimationDuration = Duration(milliseconds: 300);

  // Floating Hearts Animation
  static const Duration floatingHeartDuration = Duration(milliseconds: 1000);
  static const double heartFloatDistance = 150.0;
  static const double heartScalePeak = 1.2;
  static const double heartMaxDrift = 60.0; // Max horizontal drift in pixels
  static const double heartMaxRotation = 0.5; // Max rotation in radians (~30°)

  // Progress Bar
  static const double progressBarGestureZoneHeight = 100.0;
  static const double progressBarHeight = 3.0;
  static const double progressBarExpandedHeight = 6.0;

  // Map Configuration
  static const double defaultMapZoom = 14.0;
  static const double recenterMapZoom = 15.0;
  static const int locationDistanceFilter = 10; // meters
  static const Duration locationTimeout = Duration(seconds: 10);

  // Map FAB Positioning
  static const double mapFabBottomOffset = 100.0;

  // Location Puck
  static const double locationPuckPulsingRadius = 30.0;
  static const double locationPuckAccuracyAlpha = 0.2; // 20% opacity

  // Map Markers
  static const double mapMarkerSize =
      72.0; // Increased from 52 for better visibility
  static const double mapMarkerBorderWidth = 4.0;

  // Map Marker Pulse Animation
  /// Minimum radius for pulse animation (slightly larger than marker)
  static const double markerPulseMinRadius = 28.0;

  /// Maximum radius for pulse expansion
  static const double markerPulseMaxRadius = 44.0;

  /// Maximum opacity for pulse (fades to 0 as it expands)
  static const double markerPulseMaxOpacity = 0.35;

  /// Interval between animation frames
  static const Duration markerPulseInterval = Duration(milliseconds: 50);

  // Location Feed
  /// Radius in km for location feed nearby reports.
  static const double locationFeedRadiusKm = 1.0;

  // Camera
  static const int maxRecordingDurationSeconds = 300;

  // Report Form
  static const int maxDescriptionLength = 500;
  static const double mediaPreviewWidth = 140.0;
  static const double mediaPreviewHeight = 180.0;

  // Comments Sheet
  static const double commentsSheetInitialSize = 0.6;
  static const double commentsSheetMinSize = 0.4;
  static const double commentsSheetMaxSize = 0.9;
}
