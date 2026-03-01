# Milestone 2: Data Models & Mock Data

## Status
Completed

## Goal
Create well-structured data models (Report, Media, Comment) with typed enums, JSON serialization, and a singleton mock data service providing 10 realistic crime reports with sample videos for developing the feed UI without a backend.

## Dependencies
Requires **Milestone 1** complete (project structure, theme system, and constants exist).

## What Was Built
Three data model classes (`Report`, `Media`, `Comment`) with full JSON serialization, computed properties, and equality overrides. Three enums (`ReportType`, `MediaType`, `ReportStatus`) with display names and associated colors. A `SampleData` class with 10 hardcoded reports across 7 crime types and 31 comments, all located around San Francisco. A `MockDataService` singleton with synchronous and async query methods using Haversine distance calculations via `GeoUtils`.

## Key Files

| File | Description |
|------|-------------|
| `apps/mobile/lib/core/constants/enums.dart` | `ReportType`, `MediaType`, `ReportStatus` enums |
| `apps/mobile/lib/features/feed/data/models/report.dart` | `Report` model with `copyWith`, `fromJson`, `toJson`, computed properties |
| `apps/mobile/lib/features/feed/data/models/media.dart` | `Media` model with aspect ratio, duration helpers |
| `apps/mobile/lib/features/feed/data/models/comment.dart` | `Comment` model with `timeAgo` computed property |
| `apps/mobile/lib/shared/data/sample_data.dart` | 10 mock reports + 31 comments with real video URLs |
| `apps/mobile/lib/shared/data/mock_data_service.dart` | Singleton service with distance-based queries |
| `apps/mobile/lib/core/utils/geo_utils.dart` | Haversine distance formula and bounds checking |
| `apps/mobile/lib/core/utils/formatters.dart` | Count (K/M), distance (km→mi), duration formatters |

## Implementation Details

### Enums

Each enum carries display metadata. `ReportType` stores both a display name and an `AppColors.crimeX` color, referenced directly from the centralized color palette:

```dart
// apps/mobile/lib/core/constants/enums.dart
enum ReportType {
  theft('Theft', AppColors.crimeTheft),
  assault('Assault', AppColors.crimeAssault),
  vandalism('Vandalism', AppColors.crimeVandalism),
  suspicious('Suspicious Activity', AppColors.crimeSuspicious),
  drugActivity('Drug Activity', AppColors.crimeDrug),
  disturbance('Disturbance', AppColors.crimeDisturbance),
  other('Other', AppColors.crimeOther);

  const ReportType(this.displayName, this.color);
  final String displayName;
  final Color color;
}

enum MediaType {
  video,
  image;
  String get displayName => name[0].toUpperCase() + name.substring(1);
}

enum ReportStatus {
  pending('Pending Review'),
  verified('Verified'),
  flagged('Flagged'),
  removed('Removed');

  const ReportStatus(this.displayName);
  final String displayName;
}
```

### Report Model

The core model includes computed properties for `timeAgo`, `distanceText`, `primaryMedia`, `hasVideo`, and `hasImage`. It implements `copyWith` for immutable state updates, and `==`/`hashCode` based on `id`:

```dart
// apps/mobile/lib/features/feed/data/models/report.dart
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
  double? distanceKm;

  Media? get primaryMedia => media.isNotEmpty ? media.first : null;
  bool get hasVideo => media.any((m) => m.isVideo);
  String get timeAgo => _formatTimeAgo(createdAt);
  String get distanceText =>
      distanceKm != null ? '${distanceKm!.toStringAsFixed(1)} km' : '';

  Report copyWith({...}) => Report(id: id ?? this.id, ...);

  factory Report.fromJson(Map<String, dynamic> json) => Report(
    id: json['id'] as String,
    type: ReportType.values.byName(json['type'] as String),
    media: (json['media'] as List<dynamic>?)
        ?.map((e) => Media.fromJson(e as Map<String, dynamic>))
        .toList() ?? [],
    // ...
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'media': media.map((m) => m.toJson()).toList(),
    'created_at': createdAt.toIso8601String(),
    // ...
  };

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

### Media Model

Immutable with `const` constructor. Includes `isVideo`, `durationSeconds`, and `aspectRatio` computed getters:

```dart
// apps/mobile/lib/features/feed/data/models/media.dart
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

  const Media({required this.id, required this.reportId, ...});

  bool get isVideo => type == MediaType.video;
  double? get durationSeconds => durationMs != null ? durationMs! / 1000.0 : null;
  double get aspectRatio => width / height;

  factory Media.fromJson(Map<String, dynamic> json) => Media(...);
  Map<String, dynamic> toJson() => {...};
}
```

### Comment Model

Also immutable with `const` constructor. Has its own `_formatTimeAgo` implementation (duplicated from Report — could be extracted):

```dart
// apps/mobile/lib/features/feed/data/models/comment.dart
class Comment {
  final String id;
  final String reportId;
  final String deviceId;
  final String content;
  final int upvotes;
  final DateTime createdAt;
  final bool isReporter;

  const Comment({required this.id, ...});

  String get timeAgo => _formatTimeAgo(createdAt);

  factory Comment.fromJson(Map<String, dynamic> json) => Comment(...);
  Map<String, dynamic> toJson() => {...};
}
```

### Sample Data

`SampleData` is a pure static class with 10 reports and 31 comments. All videos use Google's public test MP4s. Locations are distributed across San Francisco neighborhoods:

```dart
// apps/mobile/lib/shared/data/sample_data.dart
class SampleData {
  SampleData._();

  static const _videoUrls = [
    'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4',
    'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerEscapes.mp4',
    // ... 8 more URLs
  ];

  static const _thumbnailUrls = [
    'https://storage.googleapis.com/gtv-videos-bucket/sample/images/ForBiggerBlazes.jpg',
    // ... 9 more thumbnail URLs
  ];

  static final List<Report> reports = [
    Report(id: 'report_001', type: ReportType.theft,
           address: 'Market St & 5th St, San Francisco', ...),
    Report(id: 'report_002', type: ReportType.assault,
           address: 'Turk St & Taylor St, San Francisco', ...),
    // ... 8 more reports covering vandalism, suspicious, drugActivity, disturbance, other
  ];

  static final List<Comment> comments = [
    // 31 comments, 3-5 per report, with isReporter flags for original reporters
  ];
}
```

Reports cover all 7 crime types: theft (2), assault (2), vandalism (2), suspicious (1), drugActivity (1), disturbance (1), other (1). Each has 1 video media item, 1920x1080, with durations from 12s to 45s.

### Mock Data Service

Singleton accessed via `MockDataService.instance`. Provides both sync and async methods (async adds simulated delays for realistic UI testing):

```dart
// apps/mobile/lib/shared/data/mock_data_service.dart
class MockDataService {
  MockDataService._internal();
  static final MockDataService instance = MockDataService._internal();

  List<Report> getReports() => List.from(SampleData.reports);
  List<Report> getReportsByRecent() { /* sorted by createdAt desc */ }
  List<Report> getReportsByPopular() { /* sorted by upvotes desc */ }

  List<Report> getNearbyReports(double lat, double lng, double radiusKm) {
    return SampleData.reports
        .map((report) {
          final distance = GeoUtils.distanceKm(lat, lng, report.latitude, report.longitude);
          return report.copyWith(distanceKm: distance);
        })
        .where((r) => r.distanceKm! <= radiusKm)
        .toList()
      ..sort((a, b) => a.distanceKm!.compareTo(b.distanceKm!));
  }

  List<Report> getReportsAtLocation(double lat, double lng, {double tolerance = 0.001}) {...}
  Report? getReportById(String id) {...}
  List<Comment> getCommentsForReport(String reportId) {...}
  List<Comment> getTopCommentsForReport(String reportId) {...}

  Future<List<Report>> getReportsAsync({Duration delay = const Duration(milliseconds: 500)}) async {...}
  Future<List<Report>> getNearbyReportsAsync(...) async {...}
  Future<List<Comment>> getCommentsAsync(...) async {...}
}
```

### GeoUtils

Haversine distance calculation used by `MockDataService.getNearbyReports`:

```dart
// apps/mobile/lib/core/utils/geo_utils.dart
class GeoUtils {
  static const double earthRadiusKm = 6371.0;

  static double distanceKm(double lat1, double lng1, double lat2, double lng2) {
    final dLat = _toRadians(lat2 - lat1);
    final dLng = _toRadians(lng2 - lng1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat1)) * cos(_toRadians(lat2)) *
        sin(dLng / 2) * sin(dLng / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadiusKm * c;
  }

  static bool isWithinBounds({required double lat, required double lng,
      required double swLat, required double swLng,
      required double neLat, required double neLng}) {...}
}
```

## Testing
No automated tests. Verification done by importing mock service in feed screen and confirming:
- 10 reports load correctly
- Video URLs are playable by `video_player`
- Distance calculations produce reasonable values
- Comments are properly linked to reports

## Notes

- **Deviation: No User model** — The original plan mentioned a User model. The implementation uses anonymous `deviceId` strings instead, matching the app's anonymous-first philosophy.
- **Deviation: Async methods** — The plan didn't call for async wrappers, but `MockDataService` provides `getReportsAsync`, `getNearbyReportsAsync`, and `getCommentsAsync` with configurable delays to simulate network latency and test loading states.
- **Deviation: Sorting methods** — `getReportsByRecent()` and `getReportsByPopular()` were added beyond the original plan.
- **Deviation: Top comments** — `getTopCommentsForReport()` was added for sorting comments by upvotes.
- **Shared `_formatTimeAgo`** — Both `Report` and `Comment` contain duplicate `_formatTimeAgo` implementations. A future refactor could extract this to `Formatters`.
- **Thumbnail URLs** — The sample data includes thumbnail URLs for each video, which wasn't in the original plan but supports future thumbnail preview features.
