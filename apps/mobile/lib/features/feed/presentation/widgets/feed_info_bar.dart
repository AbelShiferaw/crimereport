import 'package:flutter/material.dart';

import 'package:crimereport/core/theme/theme.dart';
import 'package:crimereport/core/utils/formatters.dart';
import 'package:crimereport/features/feed/data/models/report.dart';

/// Bottom info bar showing crime type, description, distance and time.
///
/// Displays over the video with text shadows for readability.
/// Shows a color-coded crime type badge.
class FeedInfoBar extends StatelessWidget {
  /// The report to display information for.
  final Report report;

  const FeedInfoBar({
    super.key,
    required this.report,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Crime type badge (color-coded)
        Container(
          padding: EdgeInsets.symmetric(
            horizontal: AppSpacing.sm + AppSpacing.xxs,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: report.type.color,
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          ),
          child: Text(
            report.type.displayName.toUpperCase(),
            style: AppTypography.labelSmall.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
        ),
        SizedBox(height: AppSpacing.sm),

        // Description (max 2 lines). Backend allows null description.
        Text(
          report.description ?? '',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.bodyMedium.copyWith(
            color: AppColors.textPrimary,
            height: 1.3,
            shadows: AppTypography.videoOverlayShadow,
          ),
        ),
        const SizedBox(height: 6),

        // Location and time row
        Row(
          children: [
            const Icon(
              Icons.location_on,
              size: 14,
              color: Colors.white70,
            ),
            const SizedBox(width: 4),
            Text(
              Formatters.distance(report.distanceKm),
              style: AppTypography.bodySmall.copyWith(
                color: Colors.white70,
              ),
            ),
            const SizedBox(width: 12),
            const Icon(
              Icons.access_time,
              size: 14,
              color: Colors.white70,
            ),
            const SizedBox(width: 4),
            Text(
              report.timeAgo,
              style: AppTypography.bodySmall.copyWith(
                color: Colors.white70,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
