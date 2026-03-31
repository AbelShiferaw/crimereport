import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:crimereport/core/constants/app_constants.dart';
import 'package:crimereport/core/theme/theme.dart';
import 'package:crimereport/features/feed/data/repositories/comment_repository.dart';
import 'package:crimereport/features/feed/providers/feed_providers.dart';
import 'package:crimereport/features/feed/providers/realtime_comments_provider.dart';
import 'package:crimereport/features/feed/presentation/widgets/comment_tile.dart';

class CommentsSheet extends ConsumerStatefulWidget {
  final String reportId;
  const CommentsSheet({super.key, required this.reportId});

  @override
  ConsumerState<CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends ConsumerState<CommentsSheet> {
  final _inputController = TextEditingController();
  final _inputFocus = FocusNode();
  bool _isSending = false;

  @override
  void dispose() {
    _inputController.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  Future<void> _submitComment() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _isSending) return;

    setState(() => _isSending = true);
    try {
      final repo = ref.read(commentRepositoryProvider);
      await repo.createComment(widget.reportId, text);
      _inputController.clear();
      _inputFocus.unfocus();
      ref.invalidate(commentsProvider(widget.reportId));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to post comment')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final commentsAsync = ref.watch(commentsProvider(widget.reportId));
    final realtimeComments = ref.watch(realtimeCommentsProvider(widget.reportId));
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    ref.listen(commentsProvider(widget.reportId), (previous, next) {
      next.whenData((comments) {
        final current = ref.read(realtimeCommentsProvider(widget.reportId));
        if (current.isEmpty && comments.isNotEmpty) {
          ref.read(realtimeCommentsProvider(widget.reportId).notifier).seed(comments);
        }
      });
    });

    final comments = realtimeComments.isNotEmpty
        ? realtimeComments
        : (commentsAsync.valueOrNull ?? []);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).pop(),
      child: DraggableScrollableSheet(
        initialChildSize: AppConstants.commentsSheetInitialSize,
        minChildSize: AppConstants.commentsSheetMinSize,
        maxChildSize: AppConstants.commentsSheetMaxSize,
        builder: (context, scrollController) {
          return AnimatedPadding(
            duration: AppConstants.fastTransition,
            padding: EdgeInsets.only(bottom: bottomInset),
            child: GestureDetector(
              onTap: () => _inputFocus.unfocus(),
              child: Container(
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(AppSpacing.radiusXl)),
                ),
                child: Column(
                  children: [
                    _buildHandle(),
                    _buildHeader(commentsAsync, comments.length),
                    const Divider(color: AppColors.divider, height: 1),
                    Expanded(
                      child: commentsAsync.when(
                        loading: _buildLoading,
                        error: (e, _) => _buildError(e),
                        data: (_) {
                          if (comments.isEmpty) return _buildEmpty();
                          return ListView.builder(
                            controller: scrollController,
                            padding: const EdgeInsets.only(top: AppSpacing.sm),
                            itemCount: comments.length,
                            itemBuilder: (_, i) => CommentTile(comment: comments[i]),
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
          width: 40, height: 4,
          decoration: BoxDecoration(
            color: AppColors.textTertiary,
            borderRadius: BorderRadius.circular(AppSpacing.radiusRound),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(AsyncValue commentsAsync, int displayCount) {
    final count = commentsAsync.isLoading ? null : displayCount;
    final label = count != null ? '$count ${count == 1 ? 'comment' : 'comments'}' : 'Comments';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm + AppSpacing.xs),
      child: Text(label, style: AppTypography.titleSmall, textAlign: TextAlign.center),
    );
  }

  Widget _buildLoading() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(AppSpacing.xxl),
        child: CircularProgressIndicator(color: AppColors.textTertiary, strokeWidth: 2),
      ),
    );
  }

  Widget _buildError(Object error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Failed to load comments', style: AppTypography.bodyMedium.copyWith(color: AppColors.textTertiary)),
            const SizedBox(height: AppSpacing.sm),
            GestureDetector(
              onTap: () => ref.invalidate(commentsProvider(widget.reportId)),
              child: Text('Tap to retry', style: AppTypography.labelMedium.copyWith(color: AppColors.primary)),
            ),
          ],
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
            Icon(Icons.chat_bubble_outline_rounded, size: AppSpacing.iconXl, color: AppColors.textDisabled),
            const SizedBox(height: AppSpacing.sm),
            Text('No comments yet', style: AppTypography.bodyMedium.copyWith(color: AppColors.textTertiary)),
            const SizedBox(height: AppSpacing.xs),
            Text('Be the first to comment', style: AppTypography.bodySmall.copyWith(color: AppColors.textDisabled)),
          ],
        ),
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm + AppSpacing.xs, vertical: AppSpacing.sm),
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
                  hintStyle: AppTypography.bodyMedium.copyWith(color: AppColors.textTertiary),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusXxl),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: AppColors.elevated,
                  contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm + AppSpacing.xxs),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            GestureDetector(
              onTap: _isSending ? null : _submitComment,
              child: Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: _isSending ? AppColors.primary.withAlpha(128) : AppColors.primary,
                  shape: BoxShape.circle,
                ),
                child: _isSending
                    ? const Padding(padding: EdgeInsets.all(10), child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.arrow_upward_rounded, color: Colors.white, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
