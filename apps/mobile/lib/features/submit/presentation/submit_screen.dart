import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/theme/theme.dart';
import 'camera_screen.dart';

class SubmitScreen extends StatefulWidget {
  const SubmitScreen({super.key});

  @override
  State<SubmitScreen> createState() => _SubmitScreenState();
}

class _SubmitScreenState extends State<SubmitScreen> {
  String? _capturedFilePath;
  bool _capturedIsVideo = false;

  Future<void> _openCamera() async {
    final cameraStatus = await Permission.camera.request();
    final micStatus = await Permission.microphone.request();

    if (!mounted) return;

    if (cameraStatus.isDenied || micStatus.isDenied) {
      _showPermissionDeniedSnackBar();
      return;
    }

    if (cameraStatus.isPermanentlyDenied || micStatus.isPermanentlyDenied) {
      _showSettingsDialog();
      return;
    }

    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(builder: (_) => const CameraScreen()),
    );

    if (result != null && mounted) {
      setState(() {
        _capturedFilePath = result['filePath'] as String;
        _capturedIsVideo = result['isVideo'] as bool;
      });
    }
  }

  void _showPermissionDeniedSnackBar() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Camera and microphone access are required'),
        backgroundColor: AppColors.surface,
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'Retry',
          textColor: AppColors.primary,
          onPressed: _openCamera,
        ),
      ),
    );
  }

  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          'Permissions Required',
          style: AppTypography.headlineSmall,
        ),
        content: Text(
          'Camera and microphone permissions are permanently denied. '
          'Please enable them in your device settings.',
          style: AppTypography.bodyMedium.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel', style: TextStyle(color: AppColors.textTertiary)),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              openAppSettings();
            },
            child: Text('Open Settings', style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );
  }

  void _clearCapture() {
    setState(() {
      _capturedFilePath = null;
      _capturedIsVideo = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
            child: _capturedFilePath != null
                ? _buildCapturedState()
                : _buildEmptyState(),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: AppColors.primary.withAlpha(25),
            borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
          ),
          child: const Icon(
            Icons.videocam_rounded,
            size: 40,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'Report a Crime',
          style: AppTypography.headlineMedium,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Capture photo or video evidence anonymously',
          style: AppTypography.bodyMedium.copyWith(
            color: AppColors.textTertiary,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.xl),
        GestureDetector(
          onTap: _openCamera,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xl,
              vertical: AppSpacing.md,
            ),
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(AppSpacing.radiusXxl),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 20),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  'Open Camera',
                  style: AppTypography.titleSmall.copyWith(color: Colors.white),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCapturedState() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Thumbnail preview
        ClipRRect(
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          child: SizedBox(
            width: 200,
            height: 260,
            child: _capturedIsVideo
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      Container(color: AppColors.surface),
                      const Center(
                        child: Icon(
                          Icons.videocam_rounded,
                          color: AppColors.textTertiary,
                          size: 48,
                        ),
                      ),
                      Positioned(
                        bottom: AppSpacing.sm,
                        left: AppSpacing.sm,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius:
                                BorderRadius.circular(AppSpacing.radiusSm),
                          ),
                          child: const Text(
                            'VIDEO',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                : Image.file(
                    File(_capturedFilePath!),
                    fit: BoxFit.cover,
                  ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          _capturedIsVideo ? 'Video captured' : 'Photo captured',
          style: AppTypography.headlineSmall,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Details form coming in next milestone',
          style: AppTypography.bodySmall.copyWith(color: AppColors.textTertiary),
        ),
        const SizedBox(height: AppSpacing.xl),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Retake
            GestureDetector(
              onTap: () {
                _clearCapture();
                _openCamera();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.sm + AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusXxl),
                  border: Border.all(color: AppColors.divider, width: 0.5),
                ),
                child: Text(
                  'Retake',
                  style: AppTypography.titleSmall,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            // Clear
            GestureDetector(
              onTap: _clearCapture,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.sm + AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusXxl),
                ),
                child: Text(
                  'Done',
                  style: AppTypography.titleSmall.copyWith(color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
