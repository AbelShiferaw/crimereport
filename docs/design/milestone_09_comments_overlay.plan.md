# Milestone 9: Comments Overlay

## Goal
Implement a slide-up bottom sheet for viewing and posting comments on crime reports.

## Dependencies
Requires **Milestone 4** complete (feed UI with comment button).

## Implementation

### 1. Comments Bottom Sheet
```dart
// lib/features/feed/presentation/widgets/comments_sheet.dart
class CommentsSheet extends StatefulWidget {
  final String reportId;
  
  @override
  State<CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<CommentsSheet> {
  final _commentController = TextEditingController();
  late List<Comment> _comments;
  
  @override
  void initState() {
    super.initState();
    _comments = MockDataService().getCommentsForReport(widget.reportId);
  }
  
  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: Color(0xFF1E1E1E),
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            children: [
              // Handle bar
              _buildHandle(),
              
              // Header
              _buildHeader(),
              
              // Comments list
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: _comments.length,
                  itemBuilder: (_, i) => CommentTile(comment: _comments[i]),
                ),
              ),
              
              // Input field
              _buildCommentInput(),
            ],
          ),
        );
      },
    );
  }
}
```

### 2. Comment Tile
```dart
// lib/features/feed/presentation/widgets/comment_tile.dart
class CommentTile extends StatelessWidget {
  final Comment comment;
  
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Anonymous avatar
          CircleAvatar(
            radius: 16,
            backgroundColor: Colors.grey[700],
            child: Text(
              'A${comment.deviceId.substring(0, 2).toUpperCase()}',
              style: TextStyle(fontSize: 10, color: Colors.white),
            ),
          ),
          SizedBox(width: 12),
          
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Username + badge
                Row(
                  children: [
                    Text(
                      'Anonymous',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    if (comment.isReporter) ...[
                      SizedBox(width: 6),
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'OP',
                          style: TextStyle(fontSize: 9, color: Colors.white),
                        ),
                      ),
                    ],
                    Spacer(),
                    Text(
                      _formatTime(comment.createdAt),
                      style: TextStyle(color: Colors.grey, fontSize: 11),
                    ),
                  ],
                ),
                SizedBox(height: 4),
                
                // Comment text
                Text(
                  comment.content,
                  style: TextStyle(color: Colors.white, fontSize: 14),
                ),
                SizedBox(height: 6),
                
                // Upvote button
                Row(
                  children: [
                    Icon(Icons.arrow_upward, size: 14, color: Colors.grey),
                    SizedBox(width: 4),
                    Text(
                      '${comment.upvotes}',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
```

### 3. Comment Input
```dart
Widget _buildCommentInput() {
  return Container(
    padding: EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Color(0xFF2A2A2A),
      border: Border(top: BorderSide(color: Colors.grey[800]!)),
    ),
    child: SafeArea(
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _commentController,
              style: TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Add a comment...',
                hintStyle: TextStyle(color: Colors.grey),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Colors.grey[800],
                contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
            ),
          ),
          SizedBox(width: 8),
          IconButton(
            onPressed: _submitComment,
            icon: Icon(Icons.send, color: Colors.red),
          ),
        ],
      ),
    ),
  );
}
```

### 4. Show Sheet from Feed
```dart
// In FeedVideoItem
void _showComments() {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => CommentsSheet(reportId: widget.report.id),
  );
}
```

## Deliverable Checklist
- [ ] Comment button opens bottom sheet
- [ ] Sheet slides up smoothly
- [ ] Can drag sheet to resize
- [ ] Comments list displays mock comments
- [ ] Anonymous avatars with initials
- [ ] "OP" badge for reporter's comments
- [ ] Timestamps shown
- [ ] Comment input field at bottom
- [ ] Send button visible (non-functional for now)
- [ ] Upvote count on comments

## Files (3 total)
1. `lib/features/feed/presentation/widgets/comments_sheet.dart` - Create
2. `lib/features/feed/presentation/widgets/comment_tile.dart` - Create
3. `lib/features/feed/presentation/widgets/feed_video_item.dart` - Update to show sheet
