import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'package:crimereport/core/constants/app_constants.dart';
import 'package:crimereport/core/theme/theme.dart';

/// Shows a preview of the captured photo or video with retake/confirm actions.
class MediaPreviewScreen extends StatefulWidget {
  final String filePath;
  final bool isVideo;

  const MediaPreviewScreen({
    super.key,
    required this.filePath,
    required this.isVideo,
  });

  @override
  State<MediaPreviewScreen> createState() => _MediaPreviewScreenState();
}

class _MediaPreviewScreenState extends State<MediaPreviewScreen>
    with WidgetsBindingObserver {
  VideoPlayerController? _videoController;
  bool _isVideoReady = false;
  bool _hasVideoError = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.isVideo) {
      _initVideo();
    }
  }

  Future<void> _initVideo() async {
    _videoController = VideoPlayerController.file(File(widget.filePath));

    try {
      await _videoController!.initialize();
      _videoController!.setLooping(true);
      _videoController!.play();
      if (mounted) setState(() => _isVideoReady = true);
    } catch (e) {
      debugPrint('Error initializing preview video: $e');
      if (mounted) setState(() => _hasVideoError = true);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!widget.isVideo) return;

    if (state == AppLifecycleState.inactive) {
      _videoController?.pause();
    } else if (state == AppLifecycleState.paused) {
      _videoController?.dispose();
      _videoController = null;
      if (mounted) setState(() => _isVideoReady = false);
    } else if (state == AppLifecycleState.resumed) {
      if (_videoController == null) {
        _initVideo();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _videoController?.dispose();
    super.dispose();
  }

  void _retake() {
    Navigator.of(context).pop();
  }

  void _useMedia() {
    // Pop back to CameraScreen with the result, which will then pop to SubmitScreen
    Navigator.of(context).pop({
      'filePath': widget.filePath,
      'isVideo': widget.isVideo,
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Preview
          if (widget.isVideo)
            _buildVideoPreview()
          else
            _buildPhotoPreview(),

          // Play/pause overlay for video
          if (widget.isVideo && _isVideoReady)
            _buildVideoPlayPause(),

          // Bottom action bar
          Positioned(
            bottom: bottomPadding + AppSpacing.xl,
            left: AppSpacing.xl,
            right: AppSpacing.xl,
            child: _buildActions(),
          ),
        ],
      ),
    );
  }

  Widget _buildPhotoPreview() {
    return Image.file(
      File(widget.filePath),
      fit: BoxFit.contain,
    );
  }

  Widget _buildVideoPreview() {
    if (_hasVideoError) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.videocam_off_rounded, color: Colors.white54, size: 48),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Unable to load video preview',
              style: AppTypography.bodyMedium.copyWith(color: Colors.white70),
            ),
            const SizedBox(height: AppSpacing.lg),
            GestureDetector(
              onTap: () {
                setState(() {
                  _hasVideoError = false;
                  _isVideoReady = false;
                });
                _initVideo();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.sm,
                ),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white38),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                ),
                child: Text(
                  'Tap to retry',
                  style: AppTypography.bodySmall.copyWith(color: Colors.white70),
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (!_isVideoReady || _videoController == null) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
      );
    }

    return Center(
      child: AspectRatio(
        aspectRatio: _videoController!.value.aspectRatio,
        child: VideoPlayer(_videoController!),
      ),
    );
  }

  Widget _buildVideoPlayPause() {
    return GestureDetector(
      onTap: () {
        setState(() {
          if (_videoController!.value.isPlaying) {
            _videoController!.pause();
          } else {
            _videoController!.play();
          }
        });
      },
      behavior: HitTestBehavior.opaque,
      child: AnimatedOpacity(
        opacity: _videoController!.value.isPlaying ? 0.0 : 1.0,
        duration: AppConstants.standardTransition,
        child: Center(
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: Colors.black.withAlpha(128),
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
    );
  }

  Widget _buildActions() {
    return Row(
      children: [
        // Retake
        Expanded(
          child: _ActionButton(
            icon: Icons.refresh_rounded,
            label: 'Retake',
            onTap: _retake,
            isPrimary: false,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        // Use this
        Expanded(
          child: _ActionButton(
            icon: Icons.check_rounded,
            label: 'Use This',
            onTap: _useMedia,
            isPrimary: true,
          ),
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isPrimary;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.isPrimary,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        decoration: BoxDecoration(
          color: isPrimary ? AppColors.primary : AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
          border: isPrimary
              ? null
              : Border.all(color: AppColors.divider, width: 0.5),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: AppSpacing.sm),
            Text(
              label,
              style: AppTypography.titleSmall.copyWith(
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
