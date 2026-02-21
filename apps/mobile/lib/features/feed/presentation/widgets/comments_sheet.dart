import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/theme.dart';
import '../../providers/feed_providers.dart';
import 'comment_tile.dart';

class CommentsSheet extends ConsumerStatefulWidget {
  final String reportId;

  const CommentsSheet({super.key, required this.reportId});

  @override
  ConsumerState<CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends ConsumerState<CommentsSheet> {
  final _inputController = TextEditingController();
  final _inputFocus = FocusNode();

  @override
  void dispose() {
    _inputController.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final commentsAsync = ref.watch(commentsProvider(widget.reportId));
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).pop(),
      child: DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        builder: (context, scrollController) {
          return AnimatedPadding(
            duration: const Duration(milliseconds: 100),
            padding: EdgeInsets.only(bottom: bottomInset),
            child: GestureDetector(
              onTap: () => _inputFocus.unfocus(),
              child: Container(
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(AppSpacing.radiusXl),
                  ),
                ),
                child: Column(
                  children: [
                    _buildHandle(),
                    _buildHeader(commentsAsync),
                    const Divider(color: AppColors.divider, height: 1),
                    Expanded(
                      child: commentsAsync.when(
                        loading: _buildLoading,
                        error: (e, _) => _buildError(e),
                        data: (comments) {
                          if (comments.isEmpty) return _buildEmpty();
                          return ListView.builder(
                            controller: scrollController,
                            padding:
                                const EdgeInsets.only(top: AppSpacing.sm),
                            itemCount: comments.length,
                            itemBuilder: (_, i) =>
                                CommentTile(comment: comments[i]),
                          );
                        },
                      ),
                    ),
                    _buildInputBar(),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHandle() {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm + AppSpacing.xs),
      child: Center(
        child: Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: AppColors.textTertiary,
            borderRadius: BorderRadius.circular(AppSpacing.radiusRound),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(AsyncValue commentsAsync) {
    final count = commentsAsync.valueOrNull?.length;
    final label = count != null
        ? '$count ${count == 1 ? 'comment' : 'comments'}'
        : 'Comments';

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm + AppSpacing.xs,
      ),
      child: Text(
        label,
        style: AppTypography.titleSmall,
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildLoading() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(AppSpacing.xxl),
        child: CircularProgressIndicator(
          color: AppColors.textTertiary,
          strokeWidth: 2,
        ),
      ),
    );
  }

  Widget _buildError(Object error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Text(
          'Failed to load comments',
          style: AppTypography.bodyMedium.copyWith(
            color: AppColors.textTertiary,
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.chat_bubble_outline_rounded,
              size: AppSpacing.iconXl,
              color: AppColors.textDisabled,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'No comments yet',
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textTertiary,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Be the first to comment',
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textDisabled,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm + AppSpacing.xs,
        vertical: AppSpacing.sm,
      ),
      decoration: const BoxDecoration(
        color: AppColors.card,
        border: Border(top: BorderSide(color: AppColors.divider, width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _inputController,
                focusNode: _inputFocus,
                style: AppTypography.bodyMedium,
                decoration: InputDecoration(
                  hintText: 'Add a comment...',
                  hintStyle: AppTypography.bodyMedium.copyWith(
                    color: AppColors.textTertiary,
                  ),
                  border: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(AppSpacing.radiusXxl),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: AppColors.elevated,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm + AppSpacing.xxs,
                  ),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            GestureDetector(
              onTap: () {
                // Non-functional for now — backend integration in Phase D
                if (_inputController.text.trim().isNotEmpty) {
                  _inputController.clear();
                  _inputFocus.unfocus();
                }
              },
              child: Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.arrow_upward_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
