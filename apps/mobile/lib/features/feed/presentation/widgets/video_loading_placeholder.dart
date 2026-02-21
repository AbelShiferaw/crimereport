import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import 'package:crimereport/core/theme/theme.dart';

/// Shimmer loading placeholder while video initializes.
class VideoLoadingPlaceholder extends StatelessWidget {
  const VideoLoadingPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.background,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Circular shimmer for play button area
            Shimmer.fromColors(
              baseColor: AppColors.shimmerBase,
              highlightColor: AppColors.shimmerHighlight,
              child: Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Text shimmer for "Loading..."
            Shimmer.fromColors(
              baseColor: AppColors.shimmerBase,
              highlightColor: AppColors.shimmerHighlight,
              child: Container(
                width: 120,
                height: 12,
                decoration: BoxDecoration(
                  color: AppColors.textPrimary,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMdSm),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
