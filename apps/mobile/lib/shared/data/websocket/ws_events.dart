import 'package:crimereport/core/constants/enums.dart';

/// Base class for report-related WebSocket events.
sealed class ReportEvent {
  const ReportEvent();

  factory ReportEvent.fromType(String eventType, Map<String, dynamic> json) {
    return switch (eventType) {
      'report:new' => NewReportEvent.fromJson(json),
      'report:upvote' => UpvoteUpdateEvent.fromJson(json),
      'media:ready' => MediaReadyEvent.fromJson(json),
      _ => throw ArgumentError('Unknown report event type: $eventType'),
    };
  }
}

class NewReportEvent extends ReportEvent {
  final String id;
  final ReportType type;
  final double lat;
  final double lng;
  final String? description;
  final int upvotes;
  final int commentCount;
  final DateTime createdAt;

  const NewReportEvent({
    required this.id,
    required this.type,
    required this.lat,
    required this.lng,
    this.description,
    required this.upvotes,
    required this.commentCount,
    required this.createdAt,
  });

  factory NewReportEvent.fromJson(Map<String, dynamic> json) {
    return NewReportEvent(
      id: json['id'] as String,
      type: ReportType.values.byName(json['type'] as String),
      lat: (json['lat'] as num).toDouble(),
      lng: (json['lng'] as num).toDouble(),
      description: json['description'] as String?,
      upvotes: json['upvotes'] as int? ?? 0,
      commentCount: json['comment_count'] as int? ?? 0,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

class UpvoteUpdateEvent extends ReportEvent {
  final String reportId;
  final bool upvoted;

  const UpvoteUpdateEvent({required this.reportId, required this.upvoted});

  factory UpvoteUpdateEvent.fromJson(Map<String, dynamic> json) {
    return UpvoteUpdateEvent(
      reportId: json['report_id'] as String,
      upvoted: json['upvoted'] as bool,
    );
  }
}

class MediaReadyEvent extends ReportEvent {
  final String reportId;
  final String? thumbnailUrl;

  const MediaReadyEvent({required this.reportId, this.thumbnailUrl});

  factory MediaReadyEvent.fromJson(Map<String, dynamic> json) {
    return MediaReadyEvent(
      reportId: json['report_id'] as String,
      thumbnailUrl: json['thumbnail_url'] as String?,
    );
  }
}

class CommentEvent {
  const CommentEvent();
}

class NewCommentEvent extends CommentEvent {
  final String id;
  final String reportId;
  final String content;
  final DateTime createdAt;

  const NewCommentEvent({
    required this.id,
    required this.reportId,
    required this.content,
    required this.createdAt,
  });

  factory NewCommentEvent.fromJson(Map<String, dynamic> json) {
    return NewCommentEvent(
      id: json['id'] as String,
      reportId: json['report_id'] as String,
      content: json['content'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
