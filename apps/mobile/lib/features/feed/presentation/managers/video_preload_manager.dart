import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

import '../../../../core/constants/app_constants.dart';
import '../../data/models/report.dart';

/// Manages video controller preloading and cleanup for smooth scrolling.
///
/// Uses an LRU cache to maintain up to [AppConstants.maxCachedVideoControllers]
/// controllers. When the cache is full, the least recently used controller
/// is disposed to make room for new ones.
class VideoPreloadManager {
  /// LRU cache - LinkedHashMap with access order maintains LRU ordering.
  /// Most recently accessed items are at the end.
  final LinkedHashMap<String, VideoPlayerController> _controllers =
      LinkedHashMap<String, VideoPlayerController>();
  final Map<String, Future<VideoPlayerController>> _pendingLoads = {};

  /// Get or create a controller for the given URL.
  ///
  /// Returns a cached controller if available, otherwise initializes a new one.
  /// Controllers are cached with LRU eviction when cache is full.
  Future<VideoPlayerController> getController(String url) async {
    // Return existing controller and mark as recently used
    if (_controllers.containsKey(url)) {
      _markAsRecentlyUsed(url);
      return _controllers[url]!;
    }

    // Return pending load if already in progress
    if (_pendingLoads.containsKey(url)) {
      return _pendingLoads[url]!;
    }

    // Evict LRU controller if cache is full
    _evictIfNeeded();

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

  /// Mark a URL as recently used by moving it to the end of the LinkedHashMap.
  void _markAsRecentlyUsed(String url) {
    final controller = _controllers.remove(url);
    if (controller != null) {
      _controllers[url] = controller;
    }
  }

  /// Evict the least recently used controller if cache is at max capacity.
  void _evictIfNeeded() {
    while (_controllers.length >= AppConstants.maxCachedVideoControllers) {
      final lruUrl = _controllers.keys.first; // First = least recently used
      final controller = _controllers.remove(lruUrl);
      controller?.dispose();
      debugPrint('LRU evicted controller: ${lruUrl.split('/').last}');
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
  /// LRU eviction happens automatically when cache is full.
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

  /// Check if a controller is ready for the given URL.
  bool isReady(String url) => _controllers.containsKey(url);

  /// Check if [controller] is the current cached instance for [url].
  /// Returns false if the URL was evicted or replaced with a new instance.
  bool isCurrent(String url, VideoPlayerController controller) {
    return _controllers[url] == controller;
  }

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
