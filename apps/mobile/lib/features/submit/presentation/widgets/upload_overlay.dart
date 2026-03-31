import 'package:flutter/material.dart';

import 'package:crimereport/core/theme/theme.dart';
import 'package:crimereport/features/submit/providers/upload_provider.dart';

class UploadOverlay extends StatelessWidget {
  final UploadState uploadState;
  final VoidCallback onCancel;
  final VoidCallback onDismiss;

  const UploadOverlay({
    super.key,
    required this.uploadState,
    required this.onCancel,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withAlpha(200),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildIcon(),
            const SizedBox(height: AppSpacing.lg),
            _buildProgress(),
            const SizedBox(height: AppSpacing.md),
            Text(
              uploadState.statusText,
              style: AppTypography.titleSmall.copyWith(
                color: AppColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            if (uploadState.phase == UploadPhase.error &&
                uploadState.errorMessage != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
                child: Text(
                  uploadState.errorMessage!,
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.xl),
            _buildAction(),
          ],
        ),
      ),
    );
  }

  Widget _buildIcon() {
    if (uploadState.phase == UploadPhase.done) {
      return Container(
        width: 64,
        height: 64,
        decoration: const BoxDecoration(
          color: AppColors.success,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.check_rounded, color: Colors.white, size: 36),
      );
    }

    if (uploadState.phase == UploadPhase.error) {
      return Container(
        width: 64,
        height: 64,
        decoration: const BoxDecoration(
          color: AppColors.error,
          shape: BoxShape.circle,
        ),
        child:
            const Icon(Icons.error_outline, color: Colors.white, size: 36),
      );
    }

    return const SizedBox(width: 64, height: 64);
  }

  Widget _buildProgress() {
    if (uploadState.phase == UploadPhase.done ||
        uploadState.phase == UploadPhase.error) {
      return const SizedBox.shrink();
    }

    final isDeterminate = uploadState.phase == UploadPhase.uploading;

    return SizedBox(
      width: 56,
      height: 56,
      child: CircularProgressIndicator(
        value: isDeterminate ? uploadState.progress : null,
        color: AppColors.primary,
        strokeWidth: 3,
        backgroundColor: AppColors.surface,
      ),
    );
  }

  Widget _buildAction() {
    if (uploadState.phase == UploadPhase.uploading) {
      return TextButton(
        onPressed: onCancel,
        child: Text(
          'Cancel',
          style: AppTypography.titleSmall.copyWith(color: AppColors.error),
        ),
      );
    }

    if (uploadState.phase == UploadPhase.error) {
      return TextButton(
        onPressed: onDismiss,
        child: Text(
          'Dismiss',
          style:
              AppTypography.titleSmall.copyWith(color: AppColors.textSecondary),
        ),
      );
    }

    return const SizedBox.shrink();
  }
}
