import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

import '../../../../core/constants/app_constants.dart';
import '../../data/models/report.dart';

/// Manages video controller preloading and cleanup for smooth scrolling.
///
/// Maintains a pool of video controllers for adjacent videos,
/// preloading ±[AppConstants.videoPreloadRange] videos and disposing
/// controllers that are far away to manage memory.
class VideoPreloadManager {
  final Map<String, VideoPlayerController> _controllers = {};
  final Map<String, Future<VideoPlayerController>> _pendingLoads = {};

  /// Get or create a controller for the given URL.
  ///
  /// Returns a cached controller if available, otherwise initializes a new one.
  /// Controllers are cached and reused for performance.
  Future<VideoPlayerController> getController(String url) async {
    // Return existing controller
    if (_controllers.containsKey(url)) {
      return _controllers[url]!;
    }

    // Return pending load if already in progress
    if (_pendingLoads.containsKey(url)) {
      return _pendingLoads[url]!;
    }

    // Start new load
    final future = _initializeController(url);
    _pendingLoads[url] = future;

    try {
      final controller = await future;
      _controllers[url] = controller;
      return controller;
    } finally {
      _pendingLoads.remove(url);
    }
  }

  Future<VideoPlayerController> _initializeController(String url) async {
    final controller = VideoPlayerController.networkUrl(
      Uri.parse(url),
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: false),
    );

    await controller.initialize();
    controller.setLooping(true);
    controller.setVolume(1.0);

    debugPrint('Initialized controller: ${url.split('/').last}');
    return controller;
  }

  /// Preload videos around the current index.
  ///
  /// Call this when the page changes to ensure smooth transitions.
  /// Videos within [AppConstants.videoPreloadRange] will be preloaded.
  void preloadAround(List<Report> reports, int currentIndex) {
    if (reports.isEmpty) return;

    final range = AppConstants.videoPreloadRange;
    final start = (currentIndex - range).clamp(0, reports.length - 1);
    final end = (currentIndex + range).clamp(0, reports.length - 1);

    // Preload videos in range
    for (int i = start; i <= end; i++) {
      final media = reports[i].primaryMedia;
      if (media != null && media.isVideo) {
        final url = media.url;
        if (!_controllers.containsKey(url) && !_pendingLoads.containsKey(url)) {
          // Fire and forget - preload in background
          _preloadVideo(url);
        }
      }
    }

    // Cleanup distant controllers
    _cleanupDistantControllers(reports, currentIndex);
  }

  /// Preload a single video in the background.
  ///
  /// Errors are logged but not propagated - preload failures are non-critical.
  Future<void> _preloadVideo(String url) async {
    try {
      await getController(url);
    } catch (e) {
      // TODO: Replace with LoggerService when crash reporting is set up
      debugPrint('Failed to preload video: $e');
      // Preload failures are non-critical - don't propagate
    }
  }

  void _cleanupDistantControllers(List<Report> reports, int currentIndex) {
    final keepRange = AppConstants.videoPreloadRange + 1;
    final keepUrls = <String>{};

    final start = (currentIndex - keepRange).clamp(0, reports.length - 1);
    final end = (currentIndex + keepRange).clamp(0, reports.length - 1);

    for (int i = start; i <= end; i++) {
      final media = reports[i].primaryMedia;
      if (media != null) {
        keepUrls.add(media.url);
      }
    }

    // Dispose controllers not in keep set
    final urlsToRemove =
        _controllers.keys.where((url) => !keepUrls.contains(url)).toList();

    for (final url in urlsToRemove) {
      _controllers[url]?.dispose();
      _controllers.remove(url);
      debugPrint('Disposed controller: ${url.split('/').last}');
    }
  }

  /// Check if a controller is ready for the given URL.
  bool isReady(String url) => _controllers.containsKey(url);

  /// Get current cache size.
  int get cacheSize => _controllers.length;

  /// Dispose all controllers and cleanup.
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    _controllers.clear();
    _pendingLoads.clear();
    debugPrint('VideoPreloadManager disposed');
  }
}
