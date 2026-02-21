import 'package:flutter/material.dart';

import 'package:crimereport/core/constants/app_constants.dart';
import 'package:crimereport/core/theme/theme.dart';

/// Capture mode: photo or video.
enum CaptureMode { photo, video }

/// Translucent circle button used in the camera top bar.
class CameraCircleButton extends StatelessWidget {
  final IconData icon;
  final String? label;
  final VoidCallback? onTap;

  const CameraCircleButton({super.key, required this.icon, this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDisabled = onTap == null;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.black.withAlpha(100),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: isDisabled ? Colors.white38 : Colors.white,
              size: 24,
            ),
          ),
          if (label != null) ...[
            const SizedBox(height: 4),
            Text(
              label!,
              style: AppTypography.caption.copyWith(
                color: Colors.white70,
                fontSize: 10,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Photo / Video mode tab selector.
class CameraModeTab extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const CameraModeTab({
    super.key,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: AppTypography.titleSmall.copyWith(
              color: isActive ? Colors.white : Colors.white54,
              fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
          const SizedBox(height: 4),
          AnimatedContainer(
            duration: AppConstants.standardTransition,
            width: isActive ? 6 : 0,
            height: 6,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }
}

/// Large capture button that toggles between photo (white) and
/// video (accent) modes, with a recording square state.
class CameraCaptureButton extends StatelessWidget {
  final CaptureMode mode;
  final bool isRecording;
  final VoidCallback onTap;

  const CameraCaptureButton({
    super.key,
    required this.mode,
    required this.isRecording,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 4),
        ),
        padding: const EdgeInsets.all(4),
        child: AnimatedContainer(
          duration: AppConstants.standardTransition,
          width: isRecording ? 32 : 64,
          height: isRecording ? 32 : 64,
          decoration: BoxDecoration(
            color: mode == CaptureMode.video ? AppColors.accent : Colors.white,
            borderRadius: BorderRadius.circular(isRecording ? 8 : 32),
          ),
        ),
      ),
    );
  }
}
