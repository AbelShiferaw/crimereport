---
name: Milestone 3 Feed Scroll
overview: Implement a TikTok-style full-screen vertical scroll feed with video autoplay, pause on scroll, and smart video preloading for smooth performance.
todos:
  - id: m3-pageview
    content: Implement PageView with vertical scroll in FeedScreen
    status: pending
    dependencies:
      - m2-verify
  - id: m3-video-item
    content: Create FeedVideoItem widget with video player
    status: pending
    dependencies:
      - m3-pageview
  - id: m3-autoplay
    content: Implement autoplay/pause based on isActive state
    status: pending
    dependencies:
      - m3-video-item
  - id: m3-preload
    content: Build VideoPreloadManager for adjacent video preloading
    status: pending
    dependencies:
      - m3-video-item
  - id: m3-loading
    content: Add shimmer loading placeholder
    status: pending
    dependencies:
      - m3-video-item
  - id: m3-verify
    content: Test smooth scrolling with mock videos
    status: pending
    dependencies:
      - m3-preload
      - m3-loading
---

# Milestone 3: TikTok Feed - Basic Scroll

## Goal
Create a full-screen vertical swipe feed where videos autoplay, pause when scrolled away, and preload adjacent videos for smooth transitions.

## Dependencies
Requires **Milestone 2** complete (mock data with video URLs available).

## Core Implementation

### 1. PageView Setup
Full-screen vertical scrolling using `PageView`:

```dart
// lib/features/feed/presentation/feed_screen.dart
class FeedScreen extends ConsumerStatefulWidget {
  @override
  ConsumerState<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends ConsumerState<FeedScreen> {
  late PageController _pageController;
  int _currentIndex = 0;
  
  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }
  
  @override
  Widget build(BuildContext context) {
    final reports = MockDataService().getReports();
    
    return PageView.builder(
      controller: _pageController,
      scrollDirection: Axis.vertical,
      itemCount: reports.length,
      onPageChanged: (index) {
        setState(() => _currentIndex = index);
      },
      itemBuilder: (context, index) {
        return FeedVideoItem(
          report: reports[index],
          isActive: index == _currentIndex,
        );
      },
    );
  }
}
```

### 2. Video Player Widget
Individual video item with playback control:

```dart
// lib/features/feed/presentation/widgets/feed_video_item.dart
class FeedVideoItem extends StatefulWidget {
  final Report report;
  final bool isActive;
  
  const FeedVideoItem({
    required this.report,
    required this.isActive,
  });
  
  @override
  State<FeedVideoItem> createState() => _FeedVideoItemState();
}

class _FeedVideoItemState extends State<FeedVideoItem> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  
  @override
  void initState() {
    super.initState();
    _initializeVideo();
  }
  
  Future<void> _initializeVideo() async {
    final videoUrl = widget.report.media.first.url;
    _controller = VideoPlayerController.networkUrl(Uri.parse(videoUrl));
    
    await _controller!.initialize();
    _controller!.setLooping(true);
    
    setState(() => _isInitialized = true);
    
    if (widget.isActive) {
      _controller!.play();
    }
  }
  
  @override
  void didUpdateWidget(FeedVideoItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Play/pause based on visibility
    if (widget.isActive && !oldWidget.isActive) {
      _controller?.play();
    } else if (!widget.isActive && oldWidget.isActive) {
      _controller?.pause();
    }
  }
  
  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: _isInitialized
          ? GestureDetector(
              onTap: _togglePlayPause,
              child: Center(
                child: AspectRatio(
                  aspectRatio: _controller!.value.aspectRatio,
                  child: VideoPlayer(_controller!),
                ),
              ),
            )
          : Center(child: CircularProgressIndicator()),
    );
  }
  
  void _togglePlayPause() {
    if (_controller!.value.isPlaying) {
      _controller!.pause();
    } else {
      _controller!.play();
    }
  }
}
```

### 3. Video Preloading Manager
Preload adjacent videos for smooth transitions:

```dart
// lib/features/feed/presentation/managers/video_preload_manager.dart
class VideoPreloadManager {
  final Map<String, VideoPlayerController> _controllers = {};
  final int _preloadRange = 1; // Preload 1 above and 1 below
  
  Future<VideoPlayerController> getController(String url) async {
    if (_controllers.containsKey(url)) {
      return _controllers[url]!;
    }
    
    final controller = VideoPlayerController.networkUrl(Uri.parse(url));
    await controller.initialize();
    controller.setLooping(true);
    _controllers[url] = controller;
    
    return controller;
  }
  
  void preloadAround(List<Report> reports, int currentIndex) {
    final start = (currentIndex - _preloadRange).clamp(0, reports.length - 1);
    final end = (currentIndex + _preloadRange).clamp(0, reports.length - 1);
    
    for (int i = start; i <= end; i++) {
      final url = reports[i].media.first.url;
      if (!_controllers.containsKey(url)) {
        getController(url); // Fire and forget preload
      }
    }
    
    // Dispose controllers outside preload range
    _cleanupDistantControllers(reports, currentIndex);
  }
  
  void _cleanupDistantControllers(List<Report> reports, int currentIndex) {
    final keepUrls = <String>{};
    for (int i = (currentIndex - _preloadRange - 1).clamp(0, reports.length - 1);
         i <= (currentIndex + _preloadRange + 1).clamp(0, reports.length - 1);
         i++) {
      keepUrls.add(reports[i].media.first.url);
    }
    
    _controllers.keys.where((url) => !keepUrls.contains(url)).toList()
      .forEach((url) {
        _controllers[url]?.dispose();
        _controllers.remove(url);
      });
  }
  
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    _controllers.clear();
  }
}
```

### 4. Loading State
Shimmer placeholder while video loads:

```dart
// lib/features/feed/presentation/widgets/video_loading_placeholder.dart
class VideoLoadingPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: Center(
        child: Shimmer.fromColors(
          baseColor: Colors.grey[800]!,
          highlightColor: Colors.grey[600]!,
          child: Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}
```

## Key Behaviors

| Behavior | Implementation |
|----------|----------------|
| Autoplay | Video plays when `isActive` becomes true |
| Pause on scroll | Video pauses when `isActive` becomes false |
| Tap to pause | `GestureDetector` toggles play/pause |
| Loop | `setLooping(true)` on controller |
| Preload | Manager preloads ±1 videos |
| Memory cleanup | Dispose controllers >2 away |

## Folder Structure Additions

```
lib/
└── features/
    └── feed/
        └── presentation/
            ├── feed_screen.dart          # Updated with PageView
            ├── widgets/
            │   ├── feed_video_item.dart  # Individual video player
            │   └── video_loading_placeholder.dart
            └── managers/
                └── video_preload_manager.dart
```

## Deliverable Checklist

- [ ] Full-screen vertical `PageView` implemented
- [ ] Videos autoplay when scrolled into view
- [ ] Videos pause when scrolled away
- [ ] Tap anywhere toggles play/pause
- [ ] Videos loop continuously
- [ ] Loading spinner/shimmer shows while buffering
- [ ] Adjacent videos preload in background
- [ ] Memory cleaned up for distant videos
- [ ] Smooth scrolling performance (60fps)
- [ ] Works with mock data videos

## Files to Create/Modify (4 total)

1. `lib/features/feed/presentation/feed_screen.dart` - Modify (add PageView)
2. `lib/features/feed/presentation/widgets/feed_video_item.dart` - Create
3. `lib/features/feed/presentation/widgets/video_loading_placeholder.dart` - Create
4. `lib/features/feed/presentation/managers/video_preload_manager.dart` - Create

---

**Approve Milestone 3?** Then I'll show you Milestone 4.