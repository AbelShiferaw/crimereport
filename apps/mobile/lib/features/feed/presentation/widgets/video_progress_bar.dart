import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/theme.dart';

/// TikTok-style seekable progress bar with large gesture zone.
///
/// The visual progress bar is thin (3px) at the bottom, but the entire
/// gesture zone height responds to horizontal drags for seeking.
/// Shows expanded bar and timestamp while dragging.
class VideoProgressBar extends StatefulWidget {
  /// The video controller to track and control.
  final VideoPlayerController? controller;

  /// Height of the invisible gesture zone.
  final double gestureZoneHeight;

  /// Normal height of the visible progress bar.
  final double barHeight;

  /// Height of the bar when user is dragging.
  final double expandedBarHeight;

  const VideoProgressBar({
    super.key,
    required this.controller,
    this.gestureZoneHeight = AppConstants.progressBarGestureZoneHeight,
    this.barHeight = AppConstants.progressBarHeight,
    this.expandedBarHeight = AppConstants.progressBarExpandedHeight,
  });

  @override
  State<VideoProgressBar> createState() => _VideoProgressBarState();
}

class _VideoProgressBarState extends State<VideoProgressBar> {
  bool _isDragging = false;
  double _dragProgress = 0.0;

  double _calculateProgress(VideoPlayerValue value) {
    if (value.duration.inMilliseconds == 0) return 0.0;
    return value.position.inMilliseconds / value.duration.inMilliseconds;
  }

  void _onHorizontalDragStart(DragStartDetails details, double width) {
    if (widget.controller == null) return;

    HapticFeedback.selectionClick();
    
    final progress = _calculateProgress(widget.controller!.value);
    setState(() {
      _isDragging = true;
      _dragProgress = progress;
    });
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details, double width) {
    if (!_isDragging || widget.controller == null || width == 0) return;

    final delta = details.delta.dx / width;
    setState(() {
      _dragProgress = (_dragProgress + delta).clamp(0.0, 1.0);
    });
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    if (widget.controller == null) return;

    HapticFeedback.lightImpact();
    
    final duration = widget.controller!.value.duration;
    final newPosition = Duration(
      milliseconds: (_dragProgress * duration.inMilliseconds).round(),
    );

    widget.controller!.seekTo(newPosition);
    setState(() => _isDragging = false);
  }

  void _onHorizontalDragCancel() {
    setState(() => _isDragging = false);
  }

  String _formatTimestamp(Duration position) {
    final minutes = position.inMinutes;
    final seconds = position.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (widget.controller == null) {
      return SizedBox(height: widget.gestureZoneHeight);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        final controller = widget.controller!;
        if (!controller.value.isInitialized) {
          return SizedBox(height: widget.gestureZoneHeight);
        }

        return ValueListenableBuilder<VideoPlayerValue>(
          valueListenable: controller,
          builder: (context, value, _) {
            final progress =
                _isDragging ? _dragProgress : _calculateProgress(value);
            final currentBarHeight =
                _isDragging ? widget.expandedBarHeight : widget.barHeight;
            
            // Calculate timestamp for drag preview
            final previewPosition = Duration(
              milliseconds: (_dragProgress * value.duration.inMilliseconds).round(),
            );

            return Semantics(
              label: 'Video progress. ${(progress * 100).round()} percent',
              slider: true,
              child: GestureDetector(
                // translucent so vertical swipes pass through to PageView
                behavior: HitTestBehavior.translucent,
                onHorizontalDragStart: (details) =>
                    _onHorizontalDragStart(details, width),
                onHorizontalDragUpdate: (details) =>
                    _onHorizontalDragUpdate(details, width),
                onHorizontalDragEnd: _onHorizontalDragEnd,
                onHorizontalDragCancel: _onHorizontalDragCancel,
                child: SizedBox(
                  height: widget.gestureZoneHeight,
                  child: Stack(
                    children: [
                      // Timestamp preview (shown when dragging)
                      if (_isDragging)
                        Positioned(
                          left: (progress * width - 30).clamp(0.0, width - 60),
                          bottom: AppSpacing.lg - AppSpacing.xs,
                          child: Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: AppSpacing.sm,
                              vertical: AppSpacing.xs,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.overlayHeavy,
                              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                            ),
                            child: Text(
                              _formatTimestamp(previewPosition),
                              style: AppTypography.labelSmall.copyWith(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      
                      // Progress bar at the bottom of the gesture zone
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: AnimatedContainer(
                          duration: AppConstants.overlayFadeDuration,
                          height: currentBarHeight,
                          child: Stack(
                            children: [
                              // Track (background)
                              Container(
                                decoration: BoxDecoration(
                                  color: AppColors.progressTrack,
                                  borderRadius:
                                      BorderRadius.circular(currentBarHeight / 2),
                                ),
                              ),

                              // Progress (foreground)
                              FractionallySizedBox(
                                widthFactor: progress.clamp(0.0, 1.0),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: AppColors.textPrimary,
                                    borderRadius:
                                        BorderRadius.circular(currentBarHeight / 2),
                                  ),
                                ),
                              ),

                              // Drag handle (when dragging)
                              if (_isDragging)
                                Positioned(
                                  left: (progress * width - 6).clamp(0.0, width - 12),
                                  top: (currentBarHeight - 12) / 2,
                                  child: Container(
                                    width: 12,
                                    height: 12,
                                    decoration: BoxDecoration(
                                      color: AppColors.textPrimary,
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: AppColors.shadowLight,
                                          blurRadius: 4,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
