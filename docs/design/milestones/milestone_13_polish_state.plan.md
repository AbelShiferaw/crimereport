# Milestone 13: Polish & State Management

## Status
Completed

## Goal
Finalize the Flutter app with a centralized theming system, Riverpod state management across features, video preload management for smooth feed scrolling, responsive utilities, and shared formatting/geo utilities.

## Dependencies
Requires **Milestones 1–12** complete (all UI screens built).

## What Was Built
- **Theming system:** Centralized `AppColors`, `AppTypography`, `AppSpacing` classes with a full Material 3 `AppTheme.darkTheme` configuration. Barrel-exported via `theme.dart`.
- **Responsive utilities:** `Responsive` class with breakpoints, device type detection, responsive value helper, and content width constraints. `DeviceType` enum with `BuildContext` extension.
- **Formatter utilities:** `Formatters` class for count abbreviation (K/M), distance (km→miles), and duration formatting.
- **Geo utilities:** `GeoUtils` with Haversine distance calculation and bounds checking.
- **Feed providers:** Riverpod providers for tab state, filtered feed reports, current feed index, video preload manager, upvote state (reports + comments), and location feed reports.
- **Map providers:** Location state/permission providers, `LocationService` class, and filtered map reports provider.
- **Video preload manager:** LRU-cached `VideoPlayerController` pool with preload-around-index strategy, pending load deduplication, and automatic eviction.
- **Shared enums:** `ReportType` (with display name + color), `MediaType`, and `ReportStatus` enums.
- **App constants:** Centralized configuration for API, map, video feed, animations, camera, comments, and UI sizing.

## Key Files
| File | Description |
|------|-------------|
| `apps/mobile/lib/core/theme/colors.dart` | `AppColors` — brand, background, text, status, crime type, overlay, glass, shadow, and gradient colors |
| `apps/mobile/lib/core/theme/typography.dart` | `AppTypography` — display, headline, title, body, label, and special text styles + video overlay shadow |
| `apps/mobile/lib/core/theme/spacing.dart` | `AppSpacing` — spacing scale, border radii, icon sizes, component sizes, touch targets, floating nav bar |
| `apps/mobile/lib/core/theme/app_theme.dart` | `AppTheme.darkTheme` — full Material 3 `ThemeData` using the above constants |
| `apps/mobile/lib/core/theme/theme.dart` | Barrel export for all theme files |
| `apps/mobile/lib/core/utils/responsive.dart` | `Responsive` breakpoints, helpers, content width; `DeviceType` enum + extension |
| `apps/mobile/lib/core/utils/formatters.dart` | `Formatters` — count, distance, duration formatting |
| `apps/mobile/lib/core/utils/geo_utils.dart` | `GeoUtils` — Haversine distance, bounds checking |
| `apps/mobile/lib/core/utils/utils.dart` | Barrel export for all utility files |
| `apps/mobile/lib/core/constants/enums.dart` | `ReportType`, `MediaType`, `ReportStatus` enums |
| `apps/mobile/lib/core/constants/app_constants.dart` | All app-wide constants |
| `apps/mobile/lib/features/feed/providers/feed_providers.dart` | Feed Riverpod providers and upvote helpers |
| `apps/mobile/lib/features/map/providers/map_providers.dart` | Map/location Riverpod providers and `LocationService` |
| `apps/mobile/lib/features/feed/presentation/managers/video_preload_manager.dart` | LRU video controller cache with preload strategy |
| `apps/mobile/lib/features/settings/providers/settings_providers.dart` | Settings providers consumed by feed and map |

## Implementation Details

### 1. Centralized Color Palette

`AppColors` is a non-instantiable class with static const colors organized by category. Crime types have dedicated colors used in chips, markers, and filters:

```dart
class AppColors {
  AppColors._();

  // Brand
  static const Color primary = Color(0xFF00897B);
  static const Color primaryLight = Color(0xFF4DB6AC);
  static const Color primaryDark = Color(0xFF00695C);

  // Accent (red for hearts, upvotes, recording indicators)
  static const Color accent = Color(0xFFE53935);

  // Background hierarchy
  static const Color background = Color(0xFF121212);
  static const Color surface = Color(0xFF1E1E1E);
  static const Color card = Color(0xFF2A2A2A);
  static const Color elevated = Color(0xFF333333);

  // Text hierarchy
  static const Color textPrimary = Colors.white;
  static const Color textSecondary = Color(0xFFB3B3B3);
  static const Color textTertiary = Color(0xFF808080);
  static const Color textDisabled = Color(0xFF4D4D4D);

  // Crime type colors
  static const Color crimeTheft = Color(0xFFFF9800);
  static const Color crimeAssault = Color(0xFFE53935);
  static const Color crimeVandalism = Color(0xFF9C27B0);
  static const Color crimeSuspicious = Color(0xFFFFC107);
  static const Color crimeDrug = Color(0xFF4CAF50);
  static const Color crimeDisturbance = Color(0xFF2196F3);
  static const Color crimeOther = Color(0xFF9E9E9E);

  // Overlay & glass UI colors for feed overlays, nav bar, badges
  static const Color navBarBackground = Color(0x80121212);
  static const Color overlayLight = Color(0x4D000000);
  static const Color overlayMedium = Color(0x80000000);
  static const Color glassBackground = Color(0x40000000);
  static const Color glassBorderLight = Color(0x26FFFFFF);
  // ... plus shadow and gradient colors
}
```

### 2. Typography System

`AppTypography` provides a comprehensive scale from display (32px) down to caption (11px), plus special styles for buttons, monospace, overline, and video overlay shadows:

```dart
class AppTypography {
  AppTypography._();

  static const String fontFamily = 'SF Pro Display';

  static const TextStyle displayLarge = TextStyle(
    fontSize: 32, fontWeight: FontWeight.bold,
    color: AppColors.textPrimary, letterSpacing: -0.5, height: 1.2,
  );
  // ... headlineLarge (24px), titleMedium (16px), bodyMedium (14px),
  //     labelMedium (12px), caption (11px), monospace, etc.

  static const List<Shadow> videoOverlayShadow = [
    Shadow(blurRadius: 4, color: Color(0x8A000000)),
  ];
}
```

### 3. Spacing and Sizing Constants

`AppSpacing` defines a consistent spacing scale, border radii, icon sizes, component sizes, and touch targets:

```dart
class AppSpacing {
  AppSpacing._();

  // Spacing scale
  static const double xxs = 2.0;
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 16.0;
  static const double lg = 24.0;
  static const double xl = 32.0;

  // Border radius
  static const double radiusSm = 4.0;
  static const double radiusMd = 8.0;
  static const double radiusLg = 12.0;
  static const double radiusXl = 16.0;
  static const double radiusXxl = 24.0;
  static const double radiusRound = 999.0;

  // Touch targets (accessibility)
  static const double minTouchTarget = 44.0;

  // Floating nav bar
  static const double floatingNavBarHeight = 64.0;
  static const double floatingNavBarSpace = 100.0;
}
```

### 4. Material 3 Theme Configuration

`AppTheme.darkTheme` assembles the above into a full `ThemeData` with configured `ColorScheme`, `AppBarTheme`, `CardThemeData`, button themes, `InputDecorationTheme`, `SnackBarThemeData`, `DialogThemeData`, `BottomSheetThemeData`, `ChipThemeData`, `SwitchThemeData`, and `ListTileThemeData`:

```dart
class AppTheme {
  AppTheme._();

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      primaryColor: AppColors.primary,
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.primary,
        secondary: AppColors.primary,
        surface: AppColors.surface,
        error: AppColors.error,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: AppTypography.titleLarge,
      ),
      // ... card, button, input, snackbar, dialog, switch themes
    );
  }
}
```

### 5. Responsive Utilities

`Responsive` provides breakpoints (mobile < 600, tablet < 1200, desktop >= 1200), device type detection, safe area helpers, and a `value<T>()` method for responsive values:

```dart
class Responsive {
  static const double mobileBreakpoint = 600;
  static const double tabletBreakpoint = 900;
  static const double desktopBreakpoint = 1200;

  static bool isMobile(BuildContext context) =>
      MediaQuery.sizeOf(context).width < mobileBreakpoint;

  static T value<T>(BuildContext context, {
    required T mobile, T? tablet, T? desktop,
  }) {
    if (isDesktop(context)) return desktop ?? tablet ?? mobile;
    if (isTablet(context)) return tablet ?? mobile;
    return mobile;
  }

  static const double maxContentWidth = 600;
}

enum DeviceType { mobile, tablet, desktop }

extension DeviceTypeExtension on BuildContext {
  DeviceType get deviceType { /* ... */ }
}
```

### 6. Feed Providers — Riverpod State Graph

Feed state is managed through several interconnected providers. `feedReportsProvider` filters mock reports by the active crime type filters from settings. `videoPreloadManagerProvider` keeps the `VideoPreloadManager` alive for the app lifecycle:

```dart
final appTabIndexProvider = StateProvider<int>((ref) => 0);

final isFeedTabActiveProvider = Provider<bool>((ref) {
  return ref.watch(appTabIndexProvider) == 0;
});

final feedReportsProvider = FutureProvider.autoDispose<List<Report>>((ref) async {
  final activeFilters = ref.watch(crimeTypeFiltersProvider);
  final reports = await MockDataService.instance.getReportsAsync();
  if (activeFilters.length == ReportType.values.length) return reports;
  return reports.where((r) => activeFilters.contains(r.type)).toList();
});

final feedCurrentIndexProvider = StateProvider<int>((ref) => 0);

final videoPreloadManagerProvider = Provider<VideoPreloadManager>((ref) {
  final manager = VideoPreloadManager();
  ref.onDispose(() => manager.dispose());
  return manager;
});

final upvotedReportsProvider = StateProvider<Set<String>>((ref) => {});

void toggleUpvote(WidgetRef ref, String reportId) {
  final notifier = ref.read(upvotedReportsProvider.notifier);
  final current = notifier.state;
  if (current.contains(reportId)) {
    notifier.state = {...current}..remove(reportId);
  } else {
    notifier.state = {...current, reportId};
  }
}
```

Comments are loaded per-report with `FutureProvider.autoDispose.family`:

```dart
final commentsProvider =
    FutureProvider.autoDispose.family<List<Comment>, String>((ref, reportId) {
  return MockDataService.instance.getCommentsAsync(reportId);
});

final upvotedCommentsProvider = StateProvider<Set<String>>((ref) => {});
```

Location feed reports are filtered and reordered with the tapped report first:

```dart
final locationFeedReportsProvider = Provider.family<List<Report>, Report>((
  ref, initialReport,
) {
  final activeFilters = ref.watch(crimeTypeFiltersProvider);
  final nearby = MockDataService.instance.getNearbyReports(
    initialReport.latitude, initialReport.longitude,
    AppConstants.locationFeedRadiusKm,
  );
  final filtered = nearby.where((r) => activeFilters.contains(r.type)).toList();
  final reordered = filtered.where((r) => r.id != initialReport.id).toList();
  if (activeFilters.contains(initialReport.type)) {
    reordered.insert(0, initialReport);
  }
  return reordered;
});
```

### 7. Map Providers — Location and Reports

`LocationService` wraps `Geolocator` for testability. `mapReportsProvider` filters reports by active crime type filters:

```dart
class LocationService {
  Future<LocationPermission> checkPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return LocationPermission.denied;
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission;
  }

  Future<Position?> getCurrentPosition() async {
    try {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(AppConstants.locationTimeout);
    } catch (e) { return null; }
  }

  Stream<Position> getPositionStream() {
    return Geolocator.getPositionStream(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: AppConstants.locationDistanceFilter,
      ),
    );
  }
}

final locationServiceProvider = Provider<LocationService>((ref) => LocationService());

final mapReportsProvider = Provider<List<Report>>((ref) {
  final activeFilters = ref.watch(crimeTypeFiltersProvider);
  final allReports = MockDataService.instance.getReports();
  if (activeFilters.length == ReportType.values.length) return allReports;
  return allReports.where((r) => activeFilters.contains(r.type)).toList();
});
```

### 8. Video Preload Manager — LRU Cache

`VideoPreloadManager` maintains a `LinkedHashMap` (LRU ordered) of up to `AppConstants.maxCachedVideoControllers` (5) controllers. It deduplicates pending loads and preloads videos around the current index:

```dart
class VideoPreloadManager {
  final LinkedHashMap<String, VideoPlayerController> _controllers =
      LinkedHashMap<String, VideoPlayerController>();
  final Map<String, Future<VideoPlayerController>> _pendingLoads = {};

  Future<VideoPlayerController> getController(String url) async {
    if (_controllers.containsKey(url)) {
      _markAsRecentlyUsed(url);
      return _controllers[url]!;
    }
    if (_pendingLoads.containsKey(url)) {
      return _pendingLoads[url]!;
    }
    _evictIfNeeded();
    final future = _initializeController(url);
    _pendingLoads[url] = future;
    try {
      final controller = await future;
      _evictIfNeeded();
      _controllers[url] = controller;
      return controller;
    } finally {
      _pendingLoads.remove(url);
    }
  }

  void _evictIfNeeded() {
    while (_controllers.length >= AppConstants.maxCachedVideoControllers) {
      final lruUrl = _controllers.keys.first;
      final controller = _controllers.remove(lruUrl);
      controller?.dispose();
    }
  }

  void preloadAround(List<Report> reports, int currentIndex) {
    if (reports.isEmpty) return;
    final range = AppConstants.videoPreloadRange;
    final start = (currentIndex - range).clamp(0, reports.length - 1);
    final end = (currentIndex + range).clamp(0, reports.length - 1);
    for (int i = start; i <= end; i++) {
      final media = reports[i].primaryMedia;
      if (media != null && media.isVideo) {
        final url = media.url;
        if (!_controllers.containsKey(url) && !_pendingLoads.containsKey(url)) {
          _preloadVideo(url);
        }
      }
    }
  }

  void dispose() {
    for (final controller in _controllers.values) { controller.dispose(); }
    _controllers.clear();
    _pendingLoads.clear();
  }
}
```

### 9. Geo Utilities — Haversine Distance

`GeoUtils` provides pure-Dart Haversine distance calculation (no external dependency) and bounds checking:

```dart
class GeoUtils {
  GeoUtils._();
  static const double earthRadiusKm = 6371.0;

  static double distanceKm(double lat1, double lng1, double lat2, double lng2) {
    final dLat = _toRadians(lat2 - lat1);
    final dLng = _toRadians(lng2 - lng1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat1)) * cos(_toRadians(lat2)) *
        sin(dLng / 2) * sin(dLng / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadiusKm * c;
  }

  static bool isWithinBounds({
    required double lat, required double lng,
    required double swLat, required double swLng,
    required double neLat, required double neLng,
  }) {
    return lat >= swLat && lat <= neLat && lng >= swLng && lng <= neLng;
  }
}
```

### 10. Formatters

`Formatters` provides count abbreviation, distance conversion (km to miles), and duration formatting:

```dart
class Formatters {
  Formatters._();

  static String count(int count) {
    if (count >= 1000000) {
      final value = count / 1000000;
      return '${value.toStringAsFixed(value.truncateToDouble() == value ? 0 : 1)}M';
    }
    if (count >= 1000) {
      final value = count / 1000;
      return '${value.toStringAsFixed(value.truncateToDouble() == value ? 0 : 1)}K';
    }
    return count.toString();
  }

  static String distance(double? km) {
    if (km == null) return '? mi';
    final miles = km * 0.621371;
    if (miles < 0.1) return '< 0.1 mi';
    return '${miles.toStringAsFixed(1)} mi';
  }

  static String duration(int milliseconds) {
    final seconds = (milliseconds / 1000).floor();
    final minutes = (seconds / 60).floor();
    final remainingSeconds = seconds % 60;
    return '$minutes:${remainingSeconds.toString().padLeft(2, '0')}';
  }
}
```

### 11. ReportType Enum with Colors

Each crime type has a `displayName` and `color` used across the app (chips, filters, map markers):

```dart
enum ReportType {
  theft('Theft', AppColors.crimeTheft),
  assault('Assault', AppColors.crimeAssault),
  vandalism('Vandalism', AppColors.crimeVandalism),
  suspicious('Suspicious Activity', AppColors.crimeSuspicious),
  drugActivity('Drug Activity', AppColors.crimeDrug),
  disturbance('Disturbance', AppColors.crimeDisturbance),
  other('Other', AppColors.crimeOther);

  const ReportType(this.displayName, this.color);
  final String displayName;
  final Color color;
}
```

## Testing
No dedicated test files were created for these utilities and providers. Manual testing required for:
- Theme consistency across all screens
- Responsive layout on different screen sizes
- Video preload manager memory behavior (max 5 cached controllers)
- Upvote state persistence within session
- Crime type filter propagation to feed and map providers

## Notes
- **Deviation from plan:** No `FlutterSecureStorage` for device ID — uses `SharedPreferences` instead (in settings providers).
- **Deviation from plan:** No `Shimmer` package or `SkeletonLoader` widget. Loading states use `CircularProgressIndicator` directly.
- **Deviation from plan:** No dedicated `ErrorView` or `EmptyFeedView` shared widgets. Error and empty states are built inline within each screen.
- **Deviation from plan:** No dedicated `page_transitions.dart` with `FadePageRoute`. Standard `MaterialPageRoute` is used throughout.
- **Deviation from plan:** No `RefreshIndicator` / pull-to-refresh on the feed (feed is a vertical video scroll, not a list).
- **Addition not in plan:** `LocationService` class wraps `Geolocator` for testability.
- **Addition not in plan:** `VideoPreloadManager` with LRU eviction, pending load deduplication, and `isCurrent()` check for stale controller detection.
- **Addition not in plan:** Comprehensive overlay/glass color palette for the feed's video-overlay UI.
- **Addition not in plan:** `Formatters.count()` for K/M abbreviations and `Formatters.distance()` for km-to-miles conversion.
- **Addition not in plan:** `GeoUtils.isWithinBounds()` for map viewport filtering.
- **Addition not in plan:** Barrel files (`theme.dart`, `utils.dart`) for clean imports.
- Haptic feedback (`HapticFeedback.lightImpact()`, `.mediumImpact()`, `.selectionClick()`) is used across camera, submit, and feed screens — not centralized but consistently applied.
- The `appTabIndexProvider` enables video pause when navigating away from the feed tab via `isFeedTabActiveProvider`.
- `AppConstants` consolidates over 40 constants including animation durations, UI dimensions, map marker sizes, and video preload configuration.
