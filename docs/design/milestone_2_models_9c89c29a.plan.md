---
name: Milestone 2 Models
overview: Define core data models (Report, Comment, Media, User) and create a mock data service with 5-10 fake crime reports including sample video URLs for testing the feed.
todos:
  - id: m2-enums
    content: Create enums for ReportType, MediaType, ReportStatus
    status: pending
    dependencies:
      - m1-verify
  - id: m2-report
    content: Implement Report model with JSON serialization
    status: pending
    dependencies:
      - m2-enums
  - id: m2-media
    content: Implement Media model for videos/images
    status: pending
    dependencies:
      - m2-enums
  - id: m2-comment
    content: Implement Comment model
    status: pending
    dependencies:
      - m2-enums
  - id: m2-sample
    content: Create sample_data.dart with 10 mock reports
    status: pending
    dependencies:
      - m2-report
      - m2-media
  - id: m2-service
    content: Build MockDataService with query methods
    status: pending
    dependencies:
      - m2-sample
      - m2-comment
  - id: m2-verify
    content: Test mock data loads correctly in app
    status: pending
    dependencies:
      - m2-service
---

# Milestone 2: Data Models & Mock Data

## Goal
Create well-structured data models and a mock data service that provides realistic test data for developing the UI without a backend.

## Dependencies
Requires **Milestone 1** to be complete (project structure exists).

## Data Models

### 1. Report Model
The core crime report entity:

```dart
// lib/features/feed/data/models/report.dart
class Report {
  final String id;
  final String deviceId;        // Anonymous reporter identifier
  final ReportType type;        // Enum: theft, assault, vandalism, etc.
  final String description;
  final double latitude;
  final double longitude;
  final String? address;        // Reverse geocoded (optional)
  final List<Media> media;      // Videos/photos
  final int upvotes;
  final int commentCount;
  final DateTime createdAt;
  final ReportStatus status;    // Enum: pending, verified, flagged
  
  // Computed property for distance from user
  double? distanceKm;
  
  Report({...});
  
  factory Report.fromJson(Map<String, dynamic> json);
  Map<String, dynamic> toJson();
}
```

### 2. Media Model
For videos and images attached to reports:

```dart
// lib/features/feed/data/models/media.dart
class Media {
  final String id;
  final String reportId;
  final MediaType type;         // Enum: video, image
  final String url;             // CDN URL
  final String? thumbnailUrl;   // For videos
  final int? durationMs;        // For videos
  final int width;
  final int height;
  final DateTime createdAt;
  
  Media({...});
  
  factory Media.fromJson(Map<String, dynamic> json);
}
```

### 3. Comment Model
For anonymous comments on reports:

```dart
// lib/features/feed/data/models/comment.dart
class Comment {
  final String id;
  final String reportId;
  final String deviceId;        // Anonymous commenter
  final String content;
  final int upvotes;
  final DateTime createdAt;
  final bool isReporter;        // True if same device as report creator
  
  Comment({...});
  
  factory Comment.fromJson(Map<String, dynamic> json);
}
```

### 4. Enums

```dart
// lib/core/constants/enums.dart
enum ReportType {
  theft,
  assault,
  vandalism,
  suspicious,
  drugActivity,
  disturbance,
  other,
}

enum MediaType { video, image }

enum ReportStatus { pending, verified, flagged, removed }
```

## Mock Data Service

### Structure

```dart
// lib/shared/data/mock_data_service.dart
class MockDataService {
  // Singleton for consistent data across app
  static final MockDataService _instance = MockDataService._internal();
  factory MockDataService() => _instance;
  
  late final List<Report> _reports;
  late final Map<String, List<Comment>> _commentsByReport;
  
  MockDataService._internal() {
    _initializeMockData();
  }
  
  // Public methods
  List<Report> getReports() => _reports;
  List<Report> getNearbyReports(double lat, double lng, double radiusKm);
  List<Report> getReportsAtLocation(double lat, double lng);
  Report? getReportById(String id);
  List<Comment> getCommentsForReport(String reportId);
  
  void _initializeMockData() {
    // Create 10 mock reports with sample videos
  }
}
```

### Sample Video URLs
Using publicly available test videos:

```dart
// Public test video URLs (MP4 format, mobile-friendly)
final sampleVideos = [
  'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4',
  'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerEscapes.mp4',
  'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerFun.mp4',
  'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerJoyrides.mp4',
  'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerMeltdowns.mp4',
  // ... more samples
];
```

### Mock Data Locations
Reports scattered around a test area (San Francisco for example):

```dart
final mockLocations = [
  {'lat': 37.7749, 'lng': -122.4194, 'address': 'Market St'},
  {'lat': 37.7849, 'lng': -122.4094, 'address': 'Union Square'},
  {'lat': 37.7649, 'lng': -122.4294, 'address': 'Castro District'},
  // ... 7 more locations
];
```

## Folder Structure Additions

```
lib/
├── features/
│   └── feed/
│       └── data/
│           └── models/
│               ├── report.dart
│               ├── media.dart
│               └── comment.dart
├── core/
│   └── constants/
│       └── enums.dart          # ReportType, MediaType, etc.
└── shared/
    └── data/
        ├── mock_data_service.dart
        └── sample_data.dart    # Raw mock data
```

## Deliverable Checklist

- [ ] `Report` model with all fields and JSON serialization
- [ ] `Media` model for videos/images
- [ ] `Comment` model for user comments
- [ ] Enums defined (`ReportType`, `MediaType`, `ReportStatus`)
- [ ] `MockDataService` singleton created
- [ ] 10 mock reports with varied crime types
- [ ] Each report has 1-3 media items (videos/images)
- [ ] 3-5 mock comments per report
- [ ] Locations spread across test area
- [ ] `getNearbyReports()` filters by distance
- [ ] Models can serialize to/from JSON (prep for API)

## Files to Create (6 total)

1. `lib/features/feed/data/models/report.dart`
2. `lib/features/feed/data/models/media.dart`
3. `lib/features/feed/data/models/comment.dart`
4. `lib/core/constants/enums.dart`
5. `lib/shared/data/mock_data_service.dart`
6. `lib/shared/data/sample_data.dart`

## Testing the Milestone

After implementation, we can verify by:
1. Importing mock service in a placeholder screen
2. Printing report count to console
3. Confirming video URLs load in browser

---

Once Milestone 1 is complete and approved, we'll implement this.