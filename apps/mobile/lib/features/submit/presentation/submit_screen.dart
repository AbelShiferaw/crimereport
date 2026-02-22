import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:crimereport/core/constants/app_constants.dart';
import 'package:crimereport/core/theme/theme.dart';
import 'package:crimereport/features/submit/presentation/camera_screen.dart';
import 'package:crimereport/features/submit/presentation/media_preview_screen.dart';
import 'package:crimereport/features/submit/presentation/report_details_screen.dart';

class SubmitScreen extends StatefulWidget {
  const SubmitScreen({super.key});

  @override
  State<SubmitScreen> createState() => _SubmitScreenState();
}

class _SubmitScreenState extends State<SubmitScreen> {
  final ImagePicker _picker = ImagePicker();
  bool _isPickerOpen = false;

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
      _navigateToDetails(
        filePath: result['filePath'] as String,
        isVideo: result['isVideo'] as bool,
      );
    }
  }

  Future<void> _openGallery() async {
    if (_isPickerOpen) return;
    HapticFeedback.lightImpact();

    final mediaType = await _showMediaTypeSheet();
    if (mediaType == null || !mounted) return;

    _isPickerOpen = true;

    try {
      final XFile? file;
      if (mediaType == _MediaType.video) {
        file = await _picker.pickVideo(
          source: ImageSource.gallery,
          maxDuration: const Duration(
            seconds: AppConstants.maxRecordingDurationSeconds,
          ),
        );
      } else {
        file = await _picker.pickImage(
          source: ImageSource.gallery,
          imageQuality: 90,
        );
      }

      _isPickerOpen = false;
      if (file == null || !mounted) return;

      final previewResult = await Navigator.of(context).push<Map<String, dynamic>>(
        MaterialPageRoute(
          builder: (_) => MediaPreviewScreen(
            filePath: file!.path,
            isVideo: mediaType == _MediaType.video,
            fromGallery: true,
          ),
        ),
      );

      if (previewResult != null && mounted) {
        _navigateToDetails(
          filePath: previewResult['filePath'] as String,
          isVideo: previewResult['isVideo'] as bool,
        );
      }
    } catch (e) {
      _isPickerOpen = false;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Could not open gallery'),
          backgroundColor: AppColors.surface,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<_MediaType?> _showMediaTypeSheet() {
    return showModalBottomSheet<_MediaType>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppSpacing.radiusXl),
        ),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'Select media type',
                style: AppTypography.titleSmall.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              ListTile(
                leading: const Icon(Icons.photo_rounded, color: AppColors.primary),
                title: Text('Photo', style: AppTypography.titleSmall),
                onTap: () => Navigator.of(ctx).pop(_MediaType.photo),
              ),
              ListTile(
                leading: const Icon(Icons.videocam_rounded, color: AppColors.primary),
                title: Text('Video', style: AppTypography.titleSmall),
                onTap: () => Navigator.of(ctx).pop(_MediaType.video),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _navigateToDetails({
    required String filePath,
    required bool isVideo,
  }) async {
    final submitted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ReportDetailsScreen(
          filePath: filePath,
          isVideo: isVideo,
        ),
      ),
    );

    if (submitted == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'Report submitted successfully',
                style: AppTypography.bodyMedium.copyWith(color: Colors.white),
              ),
            ],
          ),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
            child: _buildEmptyState(),
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
          'Capture or upload evidence anonymously',
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
        const SizedBox(height: AppSpacing.md),
        GestureDetector(
          onTap: _openGallery,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xl,
              vertical: AppSpacing.md,
            ),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppSpacing.radiusXxl),
              border: Border.all(color: AppColors.divider, width: 0.5),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.photo_library_rounded, color: AppColors.textPrimary, size: 20),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  'Upload from Gallery',
                  style: AppTypography.titleSmall,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

enum _MediaType { photo, video }
