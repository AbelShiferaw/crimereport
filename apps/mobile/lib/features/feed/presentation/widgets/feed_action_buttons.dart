import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:crimereport/core/constants/app_constants.dart';
import 'package:crimereport/core/theme/theme.dart';
import 'package:crimereport/core/utils/formatters.dart';
import 'package:crimereport/features/feed/data/models/report.dart';

/// Side action buttons for upvote, comment, and flag.
///
/// Displays vertically stacked buttons with counts on the right side
/// of the video feed. Each button has haptic feedback on tap.
class FeedActionButtons extends StatelessWidget {
  /// The report to display action counts for.
  final Report report;

  /// Whether the current user has upvoted this report.
  final bool isUpvoted;

  /// Callback when upvote button is tapped.
  final VoidCallback? onUpvote;

  /// Callback when comment button is tapped.
  final VoidCallback? onComment;

  /// Callback when flag button is tapped.
  final VoidCallback? onFlag;

  const FeedActionButtons({
    super.key,
    required this.report,
    this.isUpvoted = false,
    this.onUpvote,
    this.onComment,
    this.onFlag,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Upvote button
        _ActionButton(
          icon: Icons.arrow_upward_rounded,
          label: Formatters.count(report.upvotes),
          isActive: isUpvoted,
          activeColor: AppColors.accent,
          onTap: onUpvote,
          semanticLabel: 'Upvote. Current count: ${report.upvotes}',
        ),
        const SizedBox(height: AppConstants.feedActionButtonSpacing),

        // Comment button
        _ActionButton(
          icon: Icons.chat_bubble_outline_rounded,
          label: Formatters.count(report.commentCount),
          onTap: onComment,
          semanticLabel: 'Comments. Count: ${report.commentCount}',
        ),
        const SizedBox(height: AppConstants.feedActionButtonSpacing),

        // Flag button
        _ActionButton(
          icon: Icons.flag_outlined,
          label: 'Report',
          onTap: onFlag,
          semanticLabel: 'Report this content',
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final Color? activeColor;
  final VoidCallback? onTap;
  final String? semanticLabel;

  const _ActionButton({
    required this.icon,
    required this.label,
    this.isActive = false,
    this.activeColor,
    this.onTap,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    final color = isActive ? (activeColor ?? Colors.white) : Colors.white;

    return Semantics(
      button: true,
      label: semanticLabel,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap?.call();
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: AppConstants.feedActionButtonSize,
              height: AppConstants.feedActionButtonSize,
              decoration: BoxDecoration(
                color: AppColors.overlayLight,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: color,
                size: AppSpacing.iconLg - AppSpacing.xs,
              ),
            ),
            SizedBox(height: AppSpacing.xs),
            Text(
              label,
              style: AppTypography.labelMedium.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
                shadows: AppTypography.videoOverlayShadow,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
