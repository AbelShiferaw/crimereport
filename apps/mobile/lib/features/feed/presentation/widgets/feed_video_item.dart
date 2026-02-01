import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/theme.dart';
import '../../data/models/report.dart';
import '../../providers/feed_providers.dart';
import '../managers/video_preload_manager.dart';
import 'double_tap_like_overlay.dart';
import 'feed_action_buttons.dart';
import 'feed_info_bar.dart';
import 'video_error_placeholder.dart';
import 'video_gesture_controls.dart';
import 'video_loading_placeholder.dart';
import 'video_progress_bar.dart';

/// Individual video item in the feed with TikTok-style overlays.
///
/// Displays a full-screen video with:
/// - Long-press for 2x speed
/// - Double-tap for upvote with heart animation
/// - Tap to pause/play
/// - Side action buttons (upvote, comment, flag)
/// - Bottom info bar with crime details
/// - Seekable progress bar
class FeedVideoItem extends ConsumerStatefulWidget {
  /// The crime report to display.
  final Report report;

  /// Whether this item is currently visible/active in the feed.
  final bool isActive;

  /// Manager for video controller caching and preloading.
  final VideoPreloadManager preloadManager;

  /// Callback when comment button is tapped.
  final VoidCallback? onCommentTap;

  const FeedVideoItem({
    super.key,
    required this.report,
    required this.isActive,
    required this.preloadManager,
    this.onCommentTap,
  });

  @override
  ConsumerState<FeedVideoItem> createState() => _FeedVideoItemState();
}

class _FeedVideoItemState extends ConsumerState<FeedVideoItem> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _isBuffering = false;
  bool _hasError = false;
  String? _errorMessage;
  bool _isPaused = false;

  @override
  void initState() {
    super.initState();
    _initializeVideo();
  }

  /// Calculate bottom padding to clear the floating nav bar.
  double _getNavBarClearance(BuildContext context) {
    final bottomSafeArea = MediaQuery.of(context).padding.bottom;
    return AppConstants.feedNavBarHeight +
        bottomSafeArea +
        AppConstants.feedNavBarMargin;
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
      setState(() => _isPaused = false);
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
      setState(() => _isPaused = true);
    } else {
      _controller!.play();
      setState(() => _isPaused = false);
    }
  }

  /// Called on double-tap - only adds likes, never removes.
  /// Heart animation plays regardless.
  void _handleDoubleTapLike() {
    final upvoted = ref.read(upvotedReportsProvider);
    if (!upvoted.contains(widget.report.id)) {
      ref.read(upvotedReportsProvider.notifier).state = {
        ...upvoted,
        widget.report.id,
      };
    }
  }

  /// Called on upvote button tap - toggles like on/off.
  void _handleUpvoteButtonTap() {
    toggleUpvote(ref, widget.report.id);
  }

  void _handleFlag() {
    // TODO: Implement in Milestone 20 (Report CRUD) - show flag/report dialog
    debugPrint('Flag tapped for report: ${widget.report.id}');
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
    final isUpvoted =
        ref.watch(upvotedReportsProvider).contains(widget.report.id);
    final navBarClearance = _getNavBarClearance(context);

    return Container(
      color: AppColors.background,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Layer 1: Video or placeholder
          if (_hasError)
            VideoErrorPlaceholder(
              message: _errorMessage,
              onRetry: _retryLoad,
            )
          else if (_isInitialized && _controller != null)
            _buildVideoPlayer()
          else
            const VideoLoadingPlaceholder(),

          // Layer 2: Gesture handlers (long-press → double-tap → tap)
          if (_isInitialized && !_hasError)
            VideoGestureControls(
              controller: _controller,
              child: DoubleTapLikeOverlay(
                onDoubleTap: _handleDoubleTapLike,
                child: GestureDetector(
                  onTap: _togglePlayPause,
                  behavior: HitTestBehavior.opaque,
                  child: const SizedBox.expand(),
                ),
              ),
            ),

          // Layer 3: Buffering indicator
          if (_isBuffering && !_hasError)
            const Center(
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2,
              ),
            ),

          // Layer 4: Pause icon (shown when paused)
          // IgnorePointer lets taps pass through to gesture layer behind
          if (!_hasError && _isInitialized && _isPaused)
            IgnorePointer(
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: const BoxDecoration(
                    color: Color(0x80000000), // 50% black
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 48,
                  ),
                ),
              ),
            ),

          // Layer 5: Progress bar with large gesture zone (behind UI elements)
          // The visual bar is at the bottom, gesture zone extends upward 100px
          // Positioned BEFORE buttons/info so they receive taps
          if (_isInitialized && !_hasError)
            Positioned(
              left: 0,
              right: 0,
              bottom: navBarClearance,
              child: VideoProgressBar(
                controller: _controller,
                // Uses defaults from AppConstants
              ),
            ),

          // Layer 6: Side action buttons (right side)
            Positioned(
            right: 12,
            bottom: navBarClearance + 100,
            child: FeedActionButtons(
              report: widget.report,
              isUpvoted: isUpvoted,
              onUpvote: _handleUpvoteButtonTap,
              onComment: widget.onCommentTap,
              onFlag: _handleFlag,
            ),
          ),

          // Layer 7: Bottom info bar (left side)
          Positioned(
            left: 16,
            right: AppConstants.feedInfoBarRightMargin,
            bottom: navBarClearance + 20,
            child: FeedInfoBar(report: widget.report),
          ),
        ],
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
