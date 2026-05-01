import 'package:crimereport/core/constants/enums.dart';

/// Why a piece of media failed to process. Mirrors the
/// `failure_reason` enum on the backend `media` table.
enum MediaFailureReason {
  /// Rekognition flagged the content as inappropriate (or the
  /// pipeline deleted the upload because it was flagged).
  flaggedContent,

  /// AWS-side processing error (e.g. Rekognition outage). The
  /// user's upload is preserved and may be retried.
  processingError,

  /// The uploaded file used a codec/container the pipeline does
  /// not currently support.
  unsupportedFormat,
}

MediaFailureReason? _parseFailureReason(dynamic value) {
  if (value == null) return null;
  switch (value as String) {
    case 'flagged_content':
      return MediaFailureReason.flaggedContent;
    case 'processing_error':
      return MediaFailureReason.processingError;
    case 'unsupported_format':
      return MediaFailureReason.unsupportedFormat;
    default:
      return null;
  }
}

String? _failureReasonToJson(MediaFailureReason? reason) {
  switch (reason) {
    case MediaFailureReason.flaggedContent:
      return 'flagged_content';
    case MediaFailureReason.processingError:
      return 'processing_error';
    case MediaFailureReason.unsupportedFormat:
      return 'unsupported_format';
    case null:
      return null;
  }
}

/// Represents a media attachment (video or image) for a crime report.
class Media {
  final String id;
  final String reportId;
  final MediaType type;
  final String url;
  final String? thumbnailUrl;
  final int? durationMs;
  final int? width;
  final int? height;
  final DateTime createdAt;
  final MediaFailureReason? failureReason;

  const Media({
    required this.id,
    required this.reportId,
    required this.type,
    required this.url,
    this.thumbnailUrl,
    this.durationMs,
    this.width,
    this.height,
    required this.createdAt,
    this.failureReason,
  });

  /// Whether this media is a video (vs image).
  bool get isVideo => type == MediaType.video;

  /// Duration in seconds, or null for images.
  double? get durationSeconds =>
      durationMs != null ? durationMs! / 1000.0 : null;

  /// Aspect ratio (width / height), or null if either dimension is
  /// missing. The backend allows null width/height because dimensions
  /// may be unknown until media processing completes.
  double? get aspectRatio {
    final w = width;
    final h = height;
    if (w == null || h == null || h == 0) return null;
    return w / h;
  }

  /// Create from JSON (for API responses).
  factory Media.fromJson(Map<String, dynamic> json) => Media(
        id: json['id'] as String,
        reportId: json['report_id'] as String,
        type: MediaType.values.byName(json['type'] as String),
        url: json['url'] as String,
        thumbnailUrl: json['thumbnail_url'] as String?,
        durationMs: json['duration_ms'] as int?,
        width: json['width'] as int?,
        height: json['height'] as int?,
        createdAt: DateTime.parse(json['created_at'] as String),
        failureReason: _parseFailureReason(json['failure_reason']),
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
        'failure_reason': _failureReasonToJson(failureReason),
      };

  @override
  String toString() => 'Media(id: $id, type: ${type.name}, url: $url)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Media && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
