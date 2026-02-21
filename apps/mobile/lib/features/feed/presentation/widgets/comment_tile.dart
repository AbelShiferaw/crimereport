import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:crimereport/core/theme/theme.dart';
import 'package:crimereport/features/feed/data/models/comment.dart';
import 'package:crimereport/features/feed/providers/feed_providers.dart';

class CommentTile extends ConsumerWidget {
  final Comment comment;

  const CommentTile({super.key, required this.comment});

  /// Deterministic avatar color from the device ID hash.
  Color _avatarColor(String deviceId) {
    final colors = [
      const Color(0xFF5C6BC0),
      const Color(0xFF26A69A),
      const Color(0xFFEF5350),
      const Color(0xFFAB47BC),
      const Color(0xFF42A5F5),
      const Color(0xFFFF7043),
      const Color(0xFF66BB6A),
      const Color(0xFFFFCA28),
    ];
    return colors[deviceId.hashCode.abs() % colors.length];
  }

  String _avatarInitials(String deviceId) {
    if (deviceId.length < 2) return '??';
    return deviceId.substring(0, 2).toUpperCase();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isUpvoted =
        ref.watch(upvotedCommentsProvider).contains(comment.id);
    final displayUpvotes =
        comment.upvotes + (isUpvoted ? 1 : 0);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm + AppSpacing.xs,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avatar
          CircleAvatar(
            radius: 16,
            backgroundColor: _avatarColor(comment.deviceId),
            child: Text(
              _avatarInitials(comment.deviceId),
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm + AppSpacing.xs),

          // Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Name row
                Row(
                  children: [
                    Text(
                      'Anonymous',
                      style: AppTypography.titleSmall.copyWith(fontSize: 13),
                    ),
                    if (comment.isReporter) ...[
                      const SizedBox(width: AppSpacing.xs + 2),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1.5,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.accent,
                          borderRadius:
                              BorderRadius.circular(AppSpacing.radiusSm),
                        ),
                        child: const Text(
                          'OP',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                    const Spacer(),
                    Text(
                      comment.timeAgo,
                      style: AppTypography.caption,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),

                // Comment body
                Text(
                  comment.content,
                  style: AppTypography.bodyMedium,
                ),
                const SizedBox(height: AppSpacing.xs + 2),

                // Upvote row
                GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    toggleCommentUpvote(ref, comment.id);
                  },
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.arrow_upward_rounded,
                          size: 14,
                          color: isUpvoted
                              ? AppColors.accent
                              : AppColors.textTertiary,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Text(
                          '$displayUpvotes',
                          style: AppTypography.caption.copyWith(
                            color: isUpvoted
                                ? AppColors.accent
                                : AppColors.textTertiary,
                            fontWeight: isUpvoted
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
