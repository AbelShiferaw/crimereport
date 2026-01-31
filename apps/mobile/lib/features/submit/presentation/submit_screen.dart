import 'package:flutter/material.dart';
import '../../../core/theme/theme.dart';
import '../../../core/utils/responsive.dart';

class SubmitScreen extends StatelessWidget {
  const SubmitScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: Responsive.maxContentWidth,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: Responsive.value(context, mobile: 80.0, tablet: 100.0),
                  height: Responsive.value(
                    context,
                    mobile: 80.0,
                    tablet: 100.0,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
                  ),
                  child: Icon(
                    Icons.add_a_photo_rounded,
                    size: Responsive.value(context, mobile: 40.0, tablet: 50.0),
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'Report Crime',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Submit anonymous reports',
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.textTertiary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusXxl),
                  ),
                  child: Text(
                    'Coming in Milestone 10',
                    style: AppTypography.caption,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
