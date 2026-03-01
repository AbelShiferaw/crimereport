# Milestone 3: TikTok Feed - Basic Scroll

## Status
Completed

## Goal
Create a full-screen vertical swipe feed where videos autoplay, pause when scrolled away, and preload adjacent videos for smooth transitions. The feed is powered by Riverpod providers and uses an LRU-cached video preload manager.

## Dependencies
Requires **Milestone 2** complete (mock data with video URLs available).

## What Was Built
A `FeedScreen` with a vertical `PageView.builder` driven by Riverpod providers for reports, current index, and preload manager. A `FeedVideoItem` widget that manages video lifecycle (init, play, pause, dispose) with awareness of tab visibility. A `VideoPreloadManager` with LRU cache eviction (max 5 controllers). Shimmer loading and error placeholders. A full Riverpod provider layer (`feed_providers.dart`) for feed state including crime-type filtering, upvote tracking, and tab awareness.

## Key Files

| File | Description |
|------|-------------|
| `apps/mobile/lib/features/feed/presentation/feed_screen.dart` | PageView-based vertical feed with loading/error/empty states |
| `apps/mobile/lib/features/feed/presentation/widgets/feed_video_item.dart` | Individual video player with lifecycle management |
| `apps/mobile/lib/features/feed/presentation/managers/video_preload_manager.dart` | LRU-cached video controller manager |
| `apps/mobile/lib/features/feed/presentation/widgets/video_loading_placeholder.dart` | Shimmer loading animation |
| `apps/mobile/lib/features/feed/presentation/widgets/video_error_placeholder.dart` | Error state with retry button |
| `apps/mobile/lib/features/feed/providers/feed_providers.dart` | Riverpod providers for feed state |

## Implementation Details

### Feed Screen

`FeedScreen` is a `ConsumerStatefulWidget` that watches `feedReportsProvider` (a `FutureProvider.autoDispose` that fetches reports through `MockDataService` and filters by active crime types). It renders three states: loading, error with retry, and the main `PageView`:

```dart
// apps/mobile/lib/features/feed/presentation/feed_screen.dart
class _FeedScreenState extends ConsumerState<FeedScreen> {
  late PageController _pageController;
  bool _hasInitialPreload = false;

  void _onPageChanged(int index) {
    ref.read(feedCurrentIndexProvider.notifier).state = index;

    final reportsAsync = ref.read(feedReportsProvider);
    final preloadManager = ref.read(videoPreloadManagerProvider);
    reportsAsync.whenData((reports) {
      preloadManager.preloadAround(reports, index);
    });
  }

  @override
  Widget build(BuildContext context) {
    final reportsAsync = ref.watch(feedReportsProvider);
    final currentIndex = ref.watch(feedCurrentIndexProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      extendBodyBehindAppBar: true,
      body: reportsAsync.when(
        loading: () => _buildLoadingState(),
        error: (error, stack) => _buildErrorState(error),
        data: (reports) {
          if (reports.isEmpty) return _buildEmptyState();

          final safeIndex = currentIndex.clamp(0, reports.length - 1);

          if (!_hasInitialPreload) {
            _hasInitialPreload = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              ref.read(videoPreloadManagerProvider).preloadAround(reports, safeIndex);
            });
          }

          return PageView.builder(
            controller: _pageController,
            scrollDirection: Axis.vertical,
            itemCount: reports.length,
            onPageChanged: _onPageChanged,
            itemBuilder: (context, index) {
              return FeedVideoItem(
                key: ValueKey(reports[index].id),
                report: reports[index],
                isActive: index == safeIndex,
                preloadManager: ref.read(videoPreloadManagerProvider),
              );
            },
          );
        },
      ),
    );
  }
}
```

The empty state is context-aware — if all crime type filters are disabled, it shows a specific message with an "Enable All Filters" button. Otherwise it shows a generic "No reports yet" message.

### Feed Video Item

`FeedVideoItem` is a `ConsumerStatefulWidget` that gets its video controller from the `VideoPreloadManager` rather than creating one directly. Key behaviors:

- **Init**: Fetches controller via `preloadManager.getController()` with a timeout (`AppConstants.videoLoadTimeout = 15s`)
- **Play/Pause**: Responds to `isActive` changes via `didUpdateWidget`. When becoming active, seeks to `Duration.zero` and plays. When deactivating, pauses.
- **Tab awareness**: Listens to `isFeedTabActiveProvider` via `ref.listen`. Pauses when user navigates to another tab, resumes when returning. Has an `ignoreTabState` flag for screens pushed on the nav stack (like `LocationFeedScreen`).
- **LRU recovery**: If the controller was evicted by the LRU cache, `_isControllerValid()` detects this by checking `preloadManager.isCurrent(url, controller)`, and `_handleControllerDisposed()` re-initializes.
- **Disposal**: Only removes its listener and pauses — does NOT dispose the controller (managed by `VideoPreloadManager`).

```dart
// apps/mobile/lib/features/feed/presentation/widgets/feed_video_item.dart
class FeedVideoItem extends ConsumerStatefulWidget {
  final Report report;
  final bool isActive;
  final VideoPreloadManager preloadManager;
  final bool ignoreTabState;
  // ...
}

class _FeedVideoItemState extends ConsumerState<FeedVideoItem> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _isBuffering = false;
  bool _hasError = false;
  bool _isPaused = false;
  bool _wasPlayingBeforeTabSwitch = false;
  bool _isRecovering = false;

  Future<void> _initializeVideo() async {
    final media = widget.report.primaryMedia;
    if (media == null || !media.isVideo) { /* set error state */ return; }

    _controller = await widget.preloadManager
        .getController(media.url)
        .timeout(AppConstants.videoLoadTimeout);

    _controller!.addListener(_videoListener);
    setState(() { _isInitialized = true; _hasError = false; });

    if (widget.isActive) _controller!.play();
  }

  bool _isControllerValid() {
    if (_controller == null) return false;
    final url = widget.report.primaryMedia?.url;
    return url != null && widget.preloadManager.isCurrent(url, _controller!);
  }

  @override
  void dispose() {
    _controller?.removeListener(_videoListener);
    if (_isControllerValid()) _controller?.pause();
    // Don't dispose controller - managed by VideoPreloadManager
    super.dispose();
  }
}
```

The video player rendering handles both portrait (cover fill with `FittedBox`) and landscape (centered with `AspectRatio`) video orientations.

### Video Preload Manager

Uses a `LinkedHashMap` (access-ordered) as an LRU cache with a max size of `AppConstants.maxCachedVideoControllers` (5). Tracks pending loads to avoid duplicate initialization:

```dart
// apps/mobile/lib/features/feed/presentation/managers/video_preload_manager.dart
class VideoPreloadManager {
  final LinkedHashMap<String, VideoPlayerController> _controllers =
      LinkedHashMap<String, VideoPlayerController>();
  final Map<String, Future<VideoPlayerController>> _pendingLoads = {};

  Future<VideoPlayerController> getController(String url) async {
    if (_controllers.containsKey(url)) {
      _markAsRecentlyUsed(url);
      return _controllers[url]!;
    }
    if (_pendingLoads.containsKey(url)) return _pendingLoads[url]!;

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
    final range = AppConstants.videoPreloadRange; // ±1
    final start = (currentIndex - range).clamp(0, reports.length - 1);
    final end = (currentIndex + range).clamp(0, reports.length - 1);
    for (int i = start; i <= end; i++) {
      final media = reports[i].primaryMedia;
      if (media != null && media.isVideo) {
        final url = media.url;
        if (!_controllers.containsKey(url) && !_pendingLoads.containsKey(url)) {
          _preloadVideo(url); // fire and forget
        }
      }
    }
  }

  bool isCurrent(String url, VideoPlayerController controller) {
    return _controllers[url] == controller;
  }
}
```

Each controller is initialized with `setLooping(true)` and `setVolume(1.0)`.

### Riverpod Providers

All feed state lives in `feed_providers.dart`:

```dart
// apps/mobile/lib/features/feed/providers/feed_providers.dart

// Tab state (shared with AppShell)
final appTabIndexProvider = StateProvider<int>((ref) => 0);
final isFeedTabActiveProvider = Provider<bool>((ref) => ref.watch(appTabIndexProvider) == 0);

// Feed data (filtered by crime type from settings)
final feedReportsProvider = FutureProvider.autoDispose<List<Report>>((ref) async {
  final activeFilters = ref.watch(crimeTypeFiltersProvider);
  final reports = await MockDataService.instance.getReportsAsync();
  if (activeFilters.length == ReportType.values.length) return reports;
  return reports.where((r) => activeFilters.contains(r.type)).toList();
});

// Feed scroll position
final feedCurrentIndexProvider = StateProvider<int>((ref) => 0);

// Video manager (kept alive for app lifecycle)
final videoPreloadManagerProvider = Provider<VideoPreloadManager>((ref) {
  final manager = VideoPreloadManager();
  ref.onDispose(() => manager.dispose());
  return manager;
});

// Upvote state
final upvotedReportsProvider = StateProvider<Set<String>>((ref) => {});
void toggleUpvote(WidgetRef ref, String reportId) {...}
```

### Loading & Error Placeholders

**`VideoLoadingPlaceholder`** — Centered shimmer animation with a 64px circle and a 120px text bar, using `AppColors.shimmerBase` / `shimmerHighlight`.

**`VideoErrorPlaceholder`** — Shows a `videocam_off` icon, error message, and a "Tap to retry" button that triggers re-initialization.

## Testing
No automated tests. Manual verification:
- Vertical swiping scrolls between reports
- Videos autoplay when swiped into view
- Videos pause when swiped away
- Videos pause when switching to Map/Report/Settings tabs
- Videos resume when returning to Feed tab
- Shimmer shows while videos load
- Error state appears and retry works for failed loads
- Preloading makes adjacent video transitions smooth

## Notes

- **Deviation: Riverpod throughout** — The original plan used local state (`setState`) in `FeedScreen`. The implementation uses Riverpod providers for everything — current index, reports (with async loading), preload manager lifecycle, and tab awareness.
- **Deviation: LRU cache** — The original plan had a simple `Map` with distance-based cleanup. The implementation uses `LinkedHashMap` with proper LRU eviction, max cache size (5), and pending-load deduplication.
- **Deviation: Tab awareness** — Not in the original plan. `FeedVideoItem` pauses/resumes based on whether the Feed tab is active, using `isFeedTabActiveProvider` and `ref.listen`.
- **Deviation: Controller recovery** — Not in the original plan. When the LRU cache evicts a controller that's still referenced by a `FeedVideoItem`, the item detects this via `isCurrent()` and automatically re-initializes.
- **Deviation: Crime type filtering** — The feed respects `crimeTypeFiltersProvider` from settings, filtering reports before display.
- **Deviation: Empty state** — Context-aware empty state differentiates between "all filters off" and "no reports available".
- **Deviation: Video orientation** — Portrait videos use `FittedBox` with `BoxFit.cover` for edge-to-edge fill; landscape videos are centered with `AspectRatio` on a black background.
