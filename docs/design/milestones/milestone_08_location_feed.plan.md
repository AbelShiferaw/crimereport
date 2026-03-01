# Milestone 8: Location Feed Page

## Status
Completed

## Goal
When a user taps a marker on the map, open a full-screen vertical video feed filtered to reports near that location, with the tapped report shown first, a glass-styled header, and an X button to return to the map.

## Dependencies
Requires **Milestone 7** complete (clustering working, marker taps handled) and **Milestone 4** (feed UI with `FeedVideoItem`).

## What Was Built
A `LocationFeedScreen` (`ConsumerStatefulWidget`) that:
- Receives the tapped `Report` as a parameter
- Reads nearby reports via `locationFeedReportsProvider` (family provider keyed on the initial report)
- Displays a vertical `PageView` of `FeedVideoItem` widgets
- Integrates `VideoPreloadManager` for smooth video loading
- Overlays a glass-blur close button and location badge
- Handles lifecycle (app pause/resume) and filter changes gracefully

## Key Files

| File | Description |
|---|---|
| `apps/mobile/lib/features/map/presentation/location_feed_screen.dart` | Full-screen location feed with glass header |
| `apps/mobile/lib/features/feed/providers/feed_providers.dart` | `locationFeedReportsProvider` — filters nearby reports by crime type |
| `apps/mobile/lib/features/map/presentation/map_screen.dart` | `_onMarkerTapped()` — navigates to `LocationFeedScreen` |
| `apps/mobile/lib/features/map/providers/map_providers.dart` | `mapReportsProvider` used upstream |
| `apps/mobile/lib/core/constants/app_constants.dart` | `locationFeedRadiusKm` (1.0 km) |

## Implementation Details

### 1. Location Feed Reports Provider

A `Provider.family` keyed on the tapped `Report`. It queries `MockDataService.getNearbyReports` within a 1 km radius, applies active crime-type filters, and ensures the tapped report is first:

```dart
// feed_providers.dart
final locationFeedReportsProvider = Provider.family<List<Report>, Report>((
  ref, initialReport,
) {
  final activeFilters = ref.watch(crimeTypeFiltersProvider);
  final nearby = MockDataService.instance.getNearbyReports(
    initialReport.latitude,
    initialReport.longitude,
    AppConstants.locationFeedRadiusKm,  // 1.0
  );

  final filtered = nearby.where((r) => activeFilters.contains(r.type)).toList();

  final reordered = filtered.where((r) => r.id != initialReport.id).toList();
  if (activeFilters.contains(initialReport.type)) {
    reordered.insert(0, initialReport);
  }
  return reordered;
});
```

### 2. Navigation from Map

`MapScreen._onMarkerTapped` pre-loads videos and pushes the location feed screen:

```dart
// map_screen.dart
void _onMarkerTapped(Report report) {
  final reordered = ref.read(locationFeedReportsProvider(report));

  if (reordered.isNotEmpty) {
    ref.read(videoPreloadManagerProvider).preloadAround(reordered, 0);
  }

  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (context) => LocationFeedScreen(initialReport: report),
    ),
  );
}
```

### 3. LocationFeedScreen Widget

A `ConsumerStatefulWidget` with `WidgetsBindingObserver` for lifecycle tracking:

```dart
// location_feed_screen.dart
class LocationFeedScreen extends ConsumerStatefulWidget {
  final Report initialReport;
  const LocationFeedScreen({super.key, required this.initialReport});

  @override
  ConsumerState<LocationFeedScreen> createState() => _LocationFeedScreenState();
}

class _LocationFeedScreenState extends ConsumerState<LocationFeedScreen>
    with WidgetsBindingObserver {
  late PageController _pageController;
  int _currentIndex = 0;
  bool _isScreenActive = true;
  // ...
}
```

### 4. Vertical PageView Feed

The feed reuses the existing `FeedVideoItem` widget in a vertical `PageView`:

```dart
PageView.builder(
  controller: _pageController,
  scrollDirection: Axis.vertical,
  onPageChanged: _onPageChanged,
  itemCount: reports.length,
  itemBuilder: (context, index) {
    return FeedVideoItem(
      key: ValueKey(reports[index].id),
      report: reports[index],
      isActive: index == safeIndex && _isScreenActive,
      preloadManager: ref.read(videoPreloadManagerProvider),
      ignoreTabState: true,
    );
  },
),
```

`ignoreTabState: true` tells `FeedVideoItem` to ignore the global tab-active state (since this screen is pushed on top of the tab navigator).

### 5. Page Change & Video Preloading

```dart
void _onPageChanged(int index) {
  setState(() => _currentIndex = index);
  final reports = ref.read(locationFeedReportsProvider(widget.initialReport));
  ref.read(videoPreloadManagerProvider).preloadAround(reports, index);
}
```

### 6. Glass Close Button

A blurred circular button using `BackdropFilter`:

```dart
class _GlassCloseButton extends StatelessWidget {
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: ClipOval(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.glassBackground,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.glassBorderLight, width: 0.5),
            ),
            child: const Icon(Icons.close_rounded, color: Colors.white, size: 24),
          ),
        ),
      ),
    );
  }
}
```

### 7. Glass Location Badge

Shows the number of nearby reports with a pill-shaped glass background:

```dart
class _GlassLocationBadge extends StatelessWidget {
  final int reportCount;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xs + 2,
          ),
          decoration: BoxDecoration(
            color: AppColors.glassBackground,
            borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
            border: Border.all(color: AppColors.glassBorderLight, width: 0.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.location_on_rounded, color: Colors.white, size: 16),
              const SizedBox(width: AppSpacing.xs),
              Text('$reportCount nearby', style: AppTypography.labelMedium.copyWith(
                color: Colors.white, fontWeight: FontWeight.w500,
              )),
            ],
          ),
        ),
      ),
    );
  }
}
```

### 8. Header Layout

The header uses a symmetric `Row` with the close button on the left, location badge centered, and a spacer on the right for balance:

```dart
Positioned(
  top: topPadding + AppSpacing.sm,
  left: AppSpacing.md,
  right: AppSpacing.md,
  child: Row(
    children: [
      _GlassCloseButton(onPressed: () => Navigator.of(context).pop()),
      const Spacer(),
      _GlassLocationBadge(reportCount: reports.length),
      const Spacer(),
      const SizedBox(width: 44),  // symmetry spacer
    ],
  ),
),
```

### 9. Empty State & Index Clamping

If all reports are filtered out, a centered empty-state message is shown. The current index is clamped when the list shrinks:

```dart
if (reports.isEmpty)
  Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.filter_alt_off_rounded, size: 48, color: AppColors.textTertiary),
        const SizedBox(height: AppSpacing.md),
        Text('No reports match your filters', style: ...),
      ],
    ),
  )
```

## Navigation Flow

```
Map Screen
    │
    ▼ (tap marker)
Location Feed Screen
    │
    ├── Swipe vertically through location's videos
    │
    ▼ (tap close button)
Map Screen (pop)
```

## Testing
No dedicated unit or widget tests for `LocationFeedScreen`. The `locationFeedReportsProvider` is testable in isolation.

## Notes
- The original plan used `latitude`/`longitude`/`initialReportId` parameters. The actual implementation takes a single `Report initialReport` — the provider derives lat/lng and handles reordering.
- Glass UI (`BackdropFilter` blur) was not in the original plan — replaces the simple semi-transparent close button and location header designs.
- The close button and location badge are private widgets (`_GlassCloseButton`, `_GlassLocationBadge`) within the same file — no separate widget files were created.
- `WidgetsBindingObserver` is used to pause videos when the app goes to background.
- The feed gracefully handles the case where filters remove the tapped report or all nearby reports.
