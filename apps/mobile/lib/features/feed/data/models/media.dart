import 'package:crimereport/core/constants/enums.dart';

/// Represents a media attachment (video or image) for a crime report.
class Media {
  final String id;
  final String reportId;
  final MediaType type;
  final String url;
  final String? thumbnailUrl;
  final int? durationMs;
  final int width;
  final int height;
  final DateTime createdAt;

  const Media({
    required this.id,
    required this.reportId,
    required this.type,
    required this.url,
    this.thumbnailUrl,
    this.durationMs,
    required this.width,
    required this.height,
    required this.createdAt,
  });

  /// Whether this media is a video (vs image).
  bool get isVideo => type == MediaType.video;

  /// Duration in seconds, or null for images.
  double? get durationSeconds =>
      durationMs != null ? durationMs! / 1000.0 : null;

  /// Aspect ratio (width / height).
  double get aspectRatio => width / height;

  /// Create from JSON (for API responses).
  factory Media.fromJson(Map<String, dynamic> json) => Media(
        id: json['id'] as String,
        reportId: json['report_id'] as String,
        type: MediaType.values.byName(json['type'] as String),
        url: json['url'] as String,
        thumbnailUrl: json['thumbnail_url'] as String?,
        durationMs: json['duration_ms'] as int?,
        width: json['width'] as int,
        height: json['height'] as int,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  /// Convert to JSON (for API requests).
  Map<String, dynamic> toJson() => {
        'id': id,
        'report_id': reportId,
        'type': type.name,
        'url': url,
        'thumbnail_url': thumbnailUrl,
        'duration_ms': durationMs,
        'width': width,
        'height': height,
        'created_at': createdAt.toIso8601String(),
      };

  @override
  String toString() => 'Media(id: $id, type: ${type.name}, url: $url)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Media && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
