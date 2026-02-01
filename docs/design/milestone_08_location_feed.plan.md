# Milestone 8: Location Feed Page

## Goal

When user taps a marker on the map, open a full-screen video feed filtered to that location with an X button to return to the map.

## Dependencies

Requires **Milestone 7** complete (clustering working) and **Milestone 4** (feed UI).

## Implementation

### 1. Location Feed Screen

```dart
// lib/features/map/presentation/location_feed_screen.dart
class LocationFeedScreen extends StatelessWidget {
  final double latitude;
  final double longitude;
  final String? initialReportId;
  
  @override
  Widget build(BuildContext context) {
    // Get reports at this location
    final reports = MockDataService().getReportsAtLocation(latitude, longitude);
    
    // Find initial index if specific report tapped
    int initialIndex = 0;
    if (initialReportId != null) {
      initialIndex = reports.indexWhere((r) => r.id == initialReportId);
      if (initialIndex < 0) initialIndex = 0;
    }
    
    return Scaffold(
      body: Stack(
        children: [
          // Reuse feed component
          LocationVideoFeed(
            reports: reports,
            initialIndex: initialIndex,
          ),
          
          // Close button (top-left)
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            left: 12,
            child: CloseButton(
              onPressed: () => Navigator.pop(context),
            ),
          ),
          
          // Location header
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            left: 60,
            right: 60,
            child: LocationHeader(
              address: reports.first.address,
              reportCount: reports.length,
            ),
          ),
        ],
      ),
    );
  }
}
```

### 2. Close Button Widget

```dart
// lib/features/map/presentation/widgets/close_button.dart
class CloseButton extends StatelessWidget {
  final VoidCallback onPressed;
  
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.5),
          shape: BoxShape.circle,
        ),
        child: Icon(Icons.close, color: Colors.white, size: 20),
      ),
    );
  }
}
```

### 3. Navigation from Map

```dart
// In MapScreen marker tap handler
void _onMarkerTapped(Report report) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => LocationFeedScreen(
        latitude: report.latitude,
        longitude: report.longitude,
        initialReportId: report.id,
      ),
    ),
  );
}
```

### 4. Location Header

```dart
// lib/features/map/presentation/widgets/location_header.dart
class LocationHeader extends StatelessWidget {
  final String? address;
  final int reportCount;
  
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.5),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.location_on, color: Colors.white, size: 16),
          SizedBox(width: 4),
          Text(
            address ?? 'This Area',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          ),
          SizedBox(width: 8),
          Text(
            '• $reportCount reports',
            style: TextStyle(color: Colors.white70),
          ),
        ],
      ),
    );
  }
}
```

## Navigation Flow

```
Map Screen
    │
    ▼ (tap marker)
Location Feed Screen
    │
    ├── Swipe through location's videos
    │
    ▼ (tap X)
Map Screen (returns)
```

## Deliverable Checklist

- [ ] Tap marker → opens LocationFeedScreen
- [ ] Feed shows only reports from that location
- [ ] Initial video is the one user tapped
- [ ] Can swipe through other videos at location
- [ ] X button visible in top-left
- [ ] X button returns to map
- [ ] Location name shown in header
- [ ] Report count shown in header
- [ ] Smooth transition animation

## Files (4 total)

1. `lib/features/map/presentation/location_feed_screen.dart` - Create
2. `lib/features/map/presentation/widgets/close_button.dart` - Create
3. `lib/features/map/presentation/widgets/location_header.dart` - Create
4. `lib/features/map/presentation/map_screen.dart` - Update tap handler