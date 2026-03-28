import 'package:flutter/material.dart';

import 'package:crimereport/core/theme/theme.dart';

class NewReportBanner extends StatelessWidget {
  final VoidCallback onTap;
  final int count;

  const NewReportBanner({
    super.key,
    required this.onTap,
    this.count = 1,
  });

  @override
  Widget build(BuildContext context) {
    final label = count == 1
        ? 'New Report Nearby'
        : '$count New Reports Nearby';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: AppColors.accent,
          borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
          boxShadow: const [
            BoxShadow(
              color: AppColors.shadowMedium,
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.arrow_upward_rounded,
              color: Colors.white,
              size: 18,
            ),
            const SizedBox(width: AppSpacing.xs),
            Text(
              label,
              style: AppTypography.labelMedium.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
