import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/theme.dart';
import '../../data/models/report.dart';
import '../managers/video_preload_manager.dart';
import 'video_error_placeholder.dart';
import 'video_loading_placeholder.dart';

/// Individual video item in the feed with play/pause controls.
///
/// Handles video playback, buffering states, and user interactions.
/// Uses [VideoPreloadManager] for efficient controller caching.
class FeedVideoItem extends StatefulWidget {
  /// The crime report to display.
  final Report report;

  /// Whether this item is currently visible/active in the feed.
  final bool isActive;

  /// Manager for video controller caching and preloading.
  final VideoPreloadManager preloadManager;

  const FeedVideoItem({
    super.key,
    required this.report,
    required this.isActive,
    required this.preloadManager,
  });

  @override
  State<FeedVideoItem> createState() => _FeedVideoItemState();
}

class _FeedVideoItemState extends State<FeedVideoItem> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _isBuffering = false;
  bool _hasError = false;
  String? _errorMessage;
  bool _showPauseIcon = false;

  @override
  void initState() {
    super.initState();
    _initializeVideo();
  }

  Future<void> _initializeVideo() async {
    final media = widget.report.primaryMedia;
    if (media == null || !media.isVideo) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = 'No video available';
        });
      }
      return;
    }

    try {
      _controller = await widget.preloadManager
          .getController(media.url)
          .timeout(AppConstants.videoLoadTimeout);

      if (!mounted) return;

      _controller!.addListener(_videoListener);

      setState(() {
        _isInitialized = true;
        _hasError = false;
      });

      if (widget.isActive) {
        _controller!.play();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _hasError = true;
        _errorMessage = 'Failed to load video';
      });
      debugPrint('Error initializing video: $e');
    }
  }

  void _videoListener() {
    if (!mounted || _controller == null) return;

    final isBuffering = _controller!.value.isBuffering;
    if (isBuffering != _isBuffering) {
      setState(() => _isBuffering = isBuffering);
    }

    // Check for playback errors
    if (_controller!.value.hasError) {
      setState(() {
        _hasError = true;
        _errorMessage = 'Playback error';
      });
    }
  }

  @override
  void didUpdateWidget(FeedVideoItem oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (_controller == null || _hasError) return;

    // Play when becoming active
    if (widget.isActive && !oldWidget.isActive) {
      _controller!.seekTo(Duration.zero);
      _controller!.play();
    }
    // Pause when becoming inactive
    else if (!widget.isActive && oldWidget.isActive) {
      _controller!.pause();
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_videoListener);
    // Don't dispose controller - it's managed by VideoPreloadManager
    super.dispose();
  }

  void _togglePlayPause() {
    if (_controller == null || !_isInitialized || _hasError) return;

    if (_controller!.value.isPlaying) {
      _controller!.pause();
      setState(() => _showPauseIcon = true);
    } else {
      _controller!.play();
      setState(() => _showPauseIcon = false);
    }

    // Auto-hide pause icon after delay
    if (_showPauseIcon) {
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted && _controller?.value.isPlaying == true) {
          setState(() => _showPauseIcon = false);
        }
      });
    }
  }

  void _retryLoad() {
    setState(() {
      _hasError = false;
      _errorMessage = null;
      _isInitialized = false;
    });
    _initializeVideo();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _togglePlayPause,
      child: Container(
        color: AppColors.background,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Main content: video, loading, or error
            if (_hasError)
              VideoErrorPlaceholder(
                message: _errorMessage,
                onRetry: _retryLoad,
              )
            else if (_isInitialized && _controller != null)
              _buildVideoPlayer()
            else
              const VideoLoadingPlaceholder(),

            // Buffering indicator (overlay)
            if (_isBuffering && !_hasError)
              const Center(
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              ),

            // Play/pause icon overlay
            if (!_hasError && _isInitialized && _shouldShowPlayIcon())
              _buildPlayPauseOverlay(),
          ],
        ),
      ),
    );
  }

  bool _shouldShowPlayIcon() {
    if (_controller == null) return false;
    return _showPauseIcon || !_controller!.value.isPlaying;
  }

  Widget _buildPlayPauseOverlay() {
    final isPlaying = _controller?.value.isPlaying ?? false;

    return Center(
      child: AnimatedOpacity(
        opacity: _showPauseIcon || !isPlaying ? 0.9 : 0.0,
        duration: const Duration(milliseconds: 200),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            color: Color(0x80000000), // 50% black
            shape: BoxShape.circle,
          ),
          child: Icon(
            isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
            color: Colors.white,
            size: 48,
          ),
        ),
      ),
    );
  }

  Widget _buildVideoPlayer() {
    final controller = _controller!;
    final size = controller.value.size;

    // Handle case where size is not yet available
    if (size.width == 0 || size.height == 0) {
      return const VideoLoadingPlaceholder();
    }

    // Use BoxFit.cover for fullscreen effect (crops landscape videos)
    return FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(
        width: size.width,
        height: size.height,
        child: VideoPlayer(controller),
      ),
    );
  }
}
