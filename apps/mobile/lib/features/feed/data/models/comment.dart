/// Represents an anonymous comment on a crime report.
class Comment {
  final String id;
  final String reportId;
  final String deviceId;
  final String content;
  final int upvotes;
  final DateTime createdAt;

  /// Whether this comment was made by the original reporter.
  final bool isReporter;

  const Comment({
    required this.id,
    required this.reportId,
    required this.deviceId,
    required this.content,
    required this.upvotes,
    required this.createdAt,
    required this.isReporter,
  });

  /// Human-readable time since comment was created.
  String get timeAgo => _formatTimeAgo(createdAt);

  /// Create from JSON (for API responses).
  factory Comment.fromJson(Map<String, dynamic> json) => Comment(
        id: json['id'] as String,
        reportId: json['report_id'] as String,
        deviceId: json['device_id'] as String,
        content: json['content'] as String,
        upvotes: json['upvotes'] as int? ?? 0,
        createdAt: DateTime.parse(json['created_at'] as String),
        isReporter: json['is_reporter'] as bool? ?? false,
      );

  /// Convert to JSON (for API requests).
  Map<String, dynamic> toJson() => {
        'id': id,
        'report_id': reportId,
        'device_id': deviceId,
        'content': content,
        'upvotes': upvotes,
        'created_at': createdAt.toIso8601String(),
        'is_reporter': isReporter,
      };

  /// Format a DateTime as a human-readable "time ago" string.
  static String _formatTimeAgo(DateTime dateTime) {
    final diff = DateTime.now().difference(dateTime);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${(diff.inDays / 7).floor()}w ago';
  }

  @override
  String toString() => 'Comment(id: $id, content: ${content.substring(0, 20)}...)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Comment && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
