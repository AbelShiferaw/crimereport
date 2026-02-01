# Milestone 13: Polish & State Management

## Goal
Finalize the Flutter app with proper Riverpod state management, smooth animations, and UI polish before backend integration.

## Dependencies
Requires **Milestones 1-12** complete (all UI screens built).

## Implementation

### 1. Riverpod Provider Structure
```dart
// lib/shared/providers/providers.dart

// Device ID (anonymous identifier)
final deviceIdProvider = FutureProvider<String>((ref) async {
  final storage = FlutterSecureStorage();
  var id = await storage.read(key: 'device_id');
  if (id == null) {
    id = Uuid().v4();
    await storage.write(key: 'device_id', value: id);
  }
  return id;
});

// User location
final userLocationProvider = StreamProvider<Position>((ref) {
  return Geolocator.getPositionStream(
    locationSettings: LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 100, // Update every 100m
    ),
  );
});

// Reports provider (will connect to API later)
final reportsProvider = FutureProvider<List<Report>>((ref) async {
  // For now, return mock data
  return MockDataService().getReports();
});

// Nearby reports (filtered by location)
final nearbyReportsProvider = FutureProvider<List<Report>>((ref) async {
  final location = await ref.watch(userLocationProvider.future);
  final reports = await ref.watch(reportsProvider.future);
  
  return reports.where((r) {
    final distance = Geolocator.distanceBetween(
      location.latitude, location.longitude,
      r.latitude, r.longitude,
    );
    return distance <= 10000; // 10km radius
  }).toList();
});
```

### 2. Feed State Provider
```dart
// lib/features/feed/providers/feed_providers.dart

// Current feed index
final feedIndexProvider = StateProvider<int>((ref) => 0);

// Upvoted reports (local tracking)
final upvotedReportsProvider = StateProvider<Set<String>>((ref) => {});

// Upvote action
final upvoteReportProvider = Provider((ref) {
  return (String reportId) {
    final upvoted = ref.read(upvotedReportsProvider.notifier);
    final current = upvoted.state;
    
    if (current.contains(reportId)) {
      upvoted.state = {...current}..remove(reportId);
    } else {
      upvoted.state = {...current, reportId};
    }
  };
});
```

### 3. Animation Polish

**Page Transitions:**
```dart
// lib/core/theme/page_transitions.dart
class FadePageRoute<T> extends PageRouteBuilder<T> {
  final Widget page;
  
  FadePageRoute({required this.page})
      : super(
          pageBuilder: (_, __, ___) => page,
          transitionsBuilder: (_, animation, __, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          transitionDuration: Duration(milliseconds: 300),
        );
}
```

**Loading Skeletons:**
```dart
// lib/shared/widgets/skeleton_loader.dart
class SkeletonLoader extends StatelessWidget {
  final double width;
  final double height;
  final double borderRadius;
  
  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: Colors.grey[800]!,
      highlightColor: Colors.grey[700]!,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(borderRadius),
        ),
      ),
    );
  }
}
```

### 4. Error Handling
```dart
// lib/shared/widgets/error_view.dart
class ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 64, color: Colors.grey),
          SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(color: Colors.grey, fontSize: 16),
            textAlign: TextAlign.center,
          ),
          if (onRetry != null) ...[
            SizedBox(height: 24),
            ElevatedButton(
              onPressed: onRetry,
              child: Text('Try Again'),
            ),
          ],
        ],
      ),
    );
  }
}
```

### 5. App-Wide Refinements

**Haptic Feedback:**
```dart
// Add to button taps
HapticFeedback.lightImpact();
```

**Pull to Refresh:**
```dart
RefreshIndicator(
  onRefresh: () => ref.refresh(reportsProvider.future),
  child: feedList,
);
```

**Empty States:**
```dart
class EmptyFeedView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.videocam_off, size: 64, color: Colors.grey),
          SizedBox(height: 16),
          Text(
            'No reports nearby',
            style: TextStyle(color: Colors.white, fontSize: 18),
          ),
          Text(
            'Be the first to report',
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }
}
```

## Polish Checklist

| Area | Items |
|------|-------|
| Animations | Page transitions, button feedback, loading states |
| Error handling | Network errors, empty states, permission denied |
| Performance | Video preloading, image caching, dispose controllers |
| Accessibility | Semantic labels, touch targets ≥44pt |
| Edge cases | No location, no camera, offline mode |

## Deliverable Checklist
- [ ] All providers using Riverpod pattern
- [ ] Mock data flows through providers
- [ ] Upvote state persists locally
- [ ] Smooth page transitions
- [ ] Loading skeletons on data fetch
- [ ] Error views with retry
- [ ] Empty states for no data
- [ ] Haptic feedback on buttons
- [ ] Pull to refresh on feed
- [ ] No memory leaks (dispose controllers)
- [ ] App feels polished and responsive

## Files (6 total)
1. `lib/shared/providers/providers.dart` - Create core providers
2. `lib/features/feed/providers/feed_providers.dart` - Create feed providers
3. `lib/core/theme/page_transitions.dart` - Create transitions
4. `lib/shared/widgets/skeleton_loader.dart` - Create
5. `lib/shared/widgets/error_view.dart` - Create
6. `lib/shared/widgets/empty_state.dart` - Create
