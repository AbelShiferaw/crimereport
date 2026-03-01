# Milestone 9: Comments Overlay

## Status
Completed

## Goal
Implement a slide-up modal bottom sheet for viewing and posting comments on crime reports, with anonymous avatars, OP badges, upvoting, loading/error/empty states, and a text input bar.

## Dependencies
Requires **Milestone 4** complete (feed UI with comment button on `FeedVideoItem`).

## What Was Built
A `CommentsSheet` (`ConsumerStatefulWidget`) displayed via `showModalBottomSheet`, backed by:
- A `commentsProvider` (async family provider) that fetches comments with simulated network delay
- A `CommentTile` widget with deterministic avatar colors, OP badge, relative timestamps, and local upvote toggling
- A `Comment` model with JSON serialization and `timeAgo` formatting
- Loading spinner, error-with-retry, and empty states

## Key Files

| File | Description |
|---|---|
| `apps/mobile/lib/features/feed/presentation/widgets/comments_sheet.dart` | Modal sheet with draggable sizing, comments list, input bar |
| `apps/mobile/lib/features/feed/presentation/widgets/comment_tile.dart` | Individual comment row — avatar, name, OP badge, upvote, timestamp |
| `apps/mobile/lib/features/feed/data/models/comment.dart` | `Comment` model with `fromJson`, `toJson`, `timeAgo` |
| `apps/mobile/lib/features/feed/providers/feed_providers.dart` | `commentsProvider`, `upvotedCommentsProvider`, `toggleCommentUpvote` |
| `apps/mobile/test/features/feed/data/models/comment_test.dart` | Unit tests for Comment model |
| `apps/mobile/lib/core/constants/app_constants.dart` | Sheet sizing constants |

## Implementation Details

### 1. Comment Model

A pure Dart model with JSON serialization and a computed `timeAgo` string:

```dart
// comment.dart
class Comment {
  final String id;
  final String reportId;
  final String deviceId;
  final String content;
  final int upvotes;
  final DateTime createdAt;
  final bool isReporter;

  String get timeAgo => _formatTimeAgo(createdAt);

  factory Comment.fromJson(Map<String, dynamic> json) => Comment(
    id: json['id'] as String,
    reportId: json['report_id'] as String,
    deviceId: json['device_id'] as String,
    content: json['content'] as String,
    upvotes: json['upvotes'] as int? ?? 0,
    createdAt: DateTime.parse(json['created_at'] as String),
    isReporter: json['is_reporter'] as bool? ?? false,
  );

  static String _formatTimeAgo(DateTime dateTime) {
    final diff = DateTime.now().difference(dateTime);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${(diff.inDays / 7).floor()}w ago';
  }
}
```

### 2. Comments Provider

An auto-disposing `FutureProvider.family` that fetches comments for a given report ID:

```dart
// feed_providers.dart
final commentsProvider =
    FutureProvider.autoDispose.family<List<Comment>, String>((ref, reportId) {
  return MockDataService.instance.getCommentsAsync(reportId);
});
```

### 3. Upvote State Management

Local upvote tracking via a `StateProvider<Set<String>>` and a helper function:

```dart
final upvotedCommentsProvider = StateProvider<Set<String>>((ref) => {});

void toggleCommentUpvote(WidgetRef ref, String commentId) {
  final notifier = ref.read(upvotedCommentsProvider.notifier);
  final current = notifier.state;
  if (current.contains(commentId)) {
    notifier.state = {...current}..remove(commentId);
  } else {
    notifier.state = {...current, commentId};
  }
}
```

### 4. CommentsSheet Widget

A `DraggableScrollableSheet` inside a modal bottom sheet with configurable sizing from `AppConstants`:

```dart
// comments_sheet.dart
class CommentsSheet extends ConsumerStatefulWidget {
  final String reportId;
  const CommentsSheet({super.key, required this.reportId});
}

class _CommentsSheetState extends ConsumerState<CommentsSheet> {
  final _inputController = TextEditingController();
  final _inputFocus = FocusNode();

  @override
  Widget build(BuildContext context) {
    final commentsAsync = ref.watch(commentsProvider(widget.reportId));
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).pop(),
      child: DraggableScrollableSheet(
        initialChildSize: AppConstants.commentsSheetInitialSize,  // 0.6
        minChildSize: AppConstants.commentsSheetMinSize,          // 0.4
        maxChildSize: AppConstants.commentsSheetMaxSize,          // 0.9
        builder: (context, scrollController) {
          return AnimatedPadding(
            duration: AppConstants.fastTransition,
            padding: EdgeInsets.only(bottom: bottomInset),
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
                  Expanded(child: commentsAsync.when(
                    loading: _buildLoading,
                    error: (e, _) => _buildError(e),
                    data: (comments) {
                      if (comments.isEmpty) return _buildEmpty();
                      return ListView.builder(
                        controller: scrollController,
                        itemCount: comments.length,
                        itemBuilder: (_, i) => CommentTile(comment: comments[i]),
                      );
                    },
                  )),
                  _buildInputBar(),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
```

### 5. Loading, Error & Empty States

**Loading** — centered spinner:
```dart
Widget _buildLoading() {
  return const Center(
    child: Padding(
      padding: EdgeInsets.all(AppSpacing.xxl),
      child: CircularProgressIndicator(color: AppColors.textTertiary, strokeWidth: 2),
    ),
  );
}
```

**Error** — message with tap-to-retry that invalidates the provider:
```dart
Widget _buildError(Object error) {
  return Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Failed to load comments', style: ...),
        GestureDetector(
          onTap: () => ref.invalidate(commentsProvider(widget.reportId)),
          child: Text('Tap to retry', style: ...),
        ),
      ],
    ),
  );
}
```

**Empty** — icon and encouragement text:
```dart
Widget _buildEmpty() {
  return Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.chat_bubble_outline_rounded, size: AppSpacing.iconXl, color: AppColors.textDisabled),
        Text('No comments yet', style: ...),
        Text('Be the first to comment', style: ...),
      ],
    ),
  );
}
```

### 6. CommentTile Widget

Each comment row shows a deterministic avatar, anonymous label, optional OP badge, relative timestamp, comment body, and an upvote button:

```dart
// comment_tile.dart
class CommentTile extends ConsumerWidget {
  final Comment comment;

  Color _avatarColor(String deviceId) {
    final colors = [
      const Color(0xFF5C6BC0), const Color(0xFF26A69A),
      const Color(0xFFEF5350), const Color(0xFFAB47BC),
      const Color(0xFF42A5F5), const Color(0xFFFF7043),
      const Color(0xFF66BB6A), const Color(0xFFFFCA28),
    ];
    return colors[deviceId.hashCode.abs() % colors.length];
  }

  String _avatarInitials(String deviceId) {
    if (deviceId.length < 2) return '??';
    return deviceId.substring(0, 2).toUpperCase();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isUpvoted = ref.watch(upvotedCommentsProvider).contains(comment.id);
    final displayUpvotes = comment.upvotes + (isUpvoted ? 1 : 0);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm + AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: _avatarColor(comment.deviceId),
            child: Text(_avatarInitials(comment.deviceId), style: ...),
          ),
          // ... name row with OP badge, timestamp, body, upvote button
        ],
      ),
    );
  }
}
```

**OP Badge** — shown when `comment.isReporter` is true:
```dart
if (comment.isReporter) ...[
  const SizedBox(width: AppSpacing.xs + 2),
  Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
    decoration: BoxDecoration(
      color: AppColors.accent,
      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
    ),
    child: const Text('OP', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Colors.white)),
  ),
],
```

**Upvote Button** — toggles local state with haptic feedback:
```dart
GestureDetector(
  onTap: () {
    HapticFeedback.lightImpact();
    toggleCommentUpvote(ref, comment.id);
  },
  child: Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(Icons.arrow_upward_rounded, size: 14,
        color: isUpvoted ? AppColors.accent : AppColors.textTertiary),
      Text('$displayUpvotes', style: ...),
    ],
  ),
),
```

### 7. Comment Input Bar

A styled text field with a circular send button. Functionally clears input on tap but does not persist (backend integration deferred to Phase D):

```dart
Widget _buildInputBar() {
  return Container(
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
              decoration: InputDecoration(
                hintText: 'Add a comment...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusXxl),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: AppColors.elevated,
              ),
            ),
          ),
          GestureDetector(
            onTap: () {
              if (_inputController.text.trim().isNotEmpty) {
                _inputController.clear();
                _inputFocus.unfocus();
              }
            },
            child: Container(
              width: 40, height: 40,
              decoration: const BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.arrow_upward_rounded, color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    ),
  );
}
```

### 8. Keyboard Handling

The sheet animates its bottom padding to stay above the keyboard using `MediaQuery.of(context).viewInsets.bottom`:

```dart
AnimatedPadding(
  duration: AppConstants.fastTransition,
  padding: EdgeInsets.only(bottom: bottomInset),
  child: /* sheet content */,
),
```

## Testing

Unit tests exist for the `Comment` model at `apps/mobile/test/features/feed/data/models/comment_test.dart`:

- `timeAgo` returns a non-empty string
- Equality by `id`
- `hashCode` consistency
- `toJson` / `fromJson` roundtrip
- `fromJson` handles null optional fields (`upvotes`, `is_reporter`)
- `toString` contains id and truncated content

No widget tests for `CommentsSheet` or `CommentTile`.

## Notes
- The original plan used `MockDataService` synchronously in `initState`. The actual implementation uses an async `FutureProvider` (`commentsProvider`), enabling loading and error states.
- Upvote is fully functional client-side (toggling with haptic feedback and color change) — the original plan had it as display-only.
- Avatar colors are deterministic based on `deviceId.hashCode` (8-color palette), not random.
- The send button uses `arrow_upward_rounded` (not `send`) to match the app's visual language.
- Tapping outside the sheet (on the scrim) dismisses it via the outer `GestureDetector` + `Navigator.pop`.
- The sheet uses `AnimatedPadding` to smoothly adjust when the keyboard appears.
- The `DraggableScrollableSheet` sizing is configured via `AppConstants` (initial: 0.6, min: 0.4, max: 0.9).
