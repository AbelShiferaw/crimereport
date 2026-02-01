import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../../../../core/constants/app_constants.dart';

/// Handles long-press gesture for 2x speed playback.
///
/// Wraps child widget and intercepts long-press gestures to control
/// video playback speed. Shows a visual indicator while fast-forwarding.
class VideoGestureControls extends StatefulWidget {
  /// The video controller to control playback speed.
  final VideoPlayerController? controller;

  /// The child widget to wrap with gesture detection.
  final Widget child;

  const VideoGestureControls({
    super.key,
    required this.controller,
    required this.child,
  });

  @override
  State<VideoGestureControls> createState() => _VideoGestureControlsState();
}

class _VideoGestureControlsState extends State<VideoGestureControls> {
  bool _isFastForwarding = false;

  void _startFastForward() {
    if (widget.controller == null || !widget.controller!.value.isInitialized) {
      return;
    }

    try {
      // Haptic feedback when 2x speed activates (like TikTok)
      HapticFeedback.mediumImpact();
      
      widget.controller!.setPlaybackSpeed(2.0);
      setState(() => _isFastForwarding = true);
    } catch (e) {
      debugPrint('Failed to set playback speed: $e');
    }
  }

  void _stopFastForward() {
    if (widget.controller == null) return;

    try {
      widget.controller!.setPlaybackSpeed(1.0);
    } catch (e) {
      debugPrint('Failed to reset playback speed: $e');
    }

    if (mounted) {
      setState(() => _isFastForwarding = false);
    }
  }

  @override
  void dispose() {
    // Reset speed if disposed while fast-forwarding
    if (_isFastForwarding) {
      widget.controller?.setPlaybackSpeed(1.0);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPressStart: (_) => _startFastForward(),
      onLongPressEnd: (_) => _stopFastForward(),
      onLongPressCancel: _stopFastForward,
      child: Stack(
        children: [
          widget.child,

          // Fast-forward indicator (top-right corner badge)
          if (_isFastForwarding)
            Positioned(
              top: MediaQuery.of(context).padding.top + 12,
              right: 12,
              child: AnimatedOpacity(
                opacity: _isFastForwarding ? 1.0 : 0.0,
                duration: AppConstants.overlayFadeDuration,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0x99000000), // 60% black
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.fast_forward_rounded,
                        color: Colors.white,
                        size: 16,
                      ),
                      SizedBox(width: 4),
                      Text(
                        '2x',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
