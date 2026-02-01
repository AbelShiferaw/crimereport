import '../../../../core/constants/enums.dart';
import 'media.dart';

/// Represents a crime report with location, media, and engagement data.
class Report {
  final String id;
  final String deviceId;
  final ReportType type;
  final String description;
  final double latitude;
  final double longitude;
  final String? address;
  final List<Media> media;
  final int upvotes;
  final int commentCount;
  final DateTime createdAt;
  final ReportStatus status;

  /// Computed distance from user's location (set by MockDataService).
  double? distanceKm;

  Report({
    required this.id,
    required this.deviceId,
    required this.type,
    required this.description,
    required this.latitude,
    required this.longitude,
    this.address,
    required this.media,
    required this.upvotes,
    required this.commentCount,
    required this.createdAt,
    required this.status,
    this.distanceKm,
  });

  /// The first media item (usually the main video/image).
  Media? get primaryMedia => media.isNotEmpty ? media.first : null;

  /// Whether this report contains any video.
  bool get hasVideo => media.any((m) => m.isVideo);

  /// Whether this report contains any image.
  bool get hasImage => media.any((m) => !m.isVideo);

  /// Human-readable time since report was created.
  String get timeAgo => _formatTimeAgo(createdAt);

  /// Formatted distance string (e.g., "0.5 km" or "2.3 km").
  String get distanceText =>
      distanceKm != null ? '${distanceKm!.toStringAsFixed(1)} km' : '';

  /// Create a copy with updated fields.
  Report copyWith({
    String? id,
    String? deviceId,
    ReportType? type,
    String? description,
    double? latitude,
    double? longitude,
    String? address,
    List<Media>? media,
    int? upvotes,
    int? commentCount,
    DateTime? createdAt,
    ReportStatus? status,
    double? distanceKm,
  }) {
    return Report(
      id: id ?? this.id,
      deviceId: deviceId ?? this.deviceId,
      type: type ?? this.type,
      description: description ?? this.description,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      address: address ?? this.address,
      media: media ?? this.media,
      upvotes: upvotes ?? this.upvotes,
      commentCount: commentCount ?? this.commentCount,
      createdAt: createdAt ?? this.createdAt,
      status: status ?? this.status,
      distanceKm: distanceKm ?? this.distanceKm,
    );
  }

  /// Create from JSON (for API responses).
  factory Report.fromJson(Map<String, dynamic> json) => Report(
        id: json['id'] as String,
        deviceId: json['device_id'] as String,
        type: ReportType.values.byName(json['type'] as String),
        description: json['description'] as String,
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        address: json['address'] as String?,
        media: (json['media'] as List<dynamic>?)
                ?.map((e) => Media.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        upvotes: json['upvotes'] as int? ?? 0,
        commentCount: json['comment_count'] as int? ?? 0,
        createdAt: DateTime.parse(json['created_at'] as String),
        status: ReportStatus.values.byName(json['status'] as String),
      );

  /// Convert to JSON (for API requests).
  Map<String, dynamic> toJson() => {
        'id': id,
        'device_id': deviceId,
        'type': type.name,
        'description': description,
        'latitude': latitude,
        'longitude': longitude,
        'address': address,
        'media': media.map((m) => m.toJson()).toList(),
        'upvotes': upvotes,
        'comment_count': commentCount,
        'created_at': createdAt.toIso8601String(),
        'status': status.name,
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
  String toString() => 'Report(id: $id, type: ${type.name}, address: $address)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Report && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
