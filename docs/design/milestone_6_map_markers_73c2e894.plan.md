---
name: Milestone 6 Map Markers
overview: Display circular thumbnail markers on the map at crime report locations, with tap detection to log marker info to console.
todos:
  - id: m6-marker-widget
    content: Create CrimeMarker circular thumbnail widget
    status: pending
  - id: m6-add-markers
    content: Add markers to map from mock data
    status: pending
  - id: m6-tap
    content: Implement marker tap detection
    status: pending
  - id: m6-verify
    content: Test markers display and respond to taps
    status: pending
---

# Milestone 6: Mapbox Map - Crime Markers

## Goal
Show circular video/image thumbnails as markers on the map at each crime location.

## Dependencies
Requires **Milestone 5** complete (map displaying).

## Implementation

### 1. Custom Marker Widget
```dart
// lib/features/map/presentation/widgets/crime_marker.dart
class CrimeMarker extends StatelessWidget {
  final Report report;
  final double size;
  
  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: _getBorderColor(report.type), width: 3),
        boxShadow: [BoxShadow(blurRadius: 4, color: Colors.black45)],
      ),
      child: ClipOval(
        child: CachedNetworkImage(
          imageUrl: report.media.first.thumbnailUrl ?? report.media.first.url,
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}
```

### 2. Add Markers to Map
```dart
// In MapScreen
void _addCrimeMarkers() async {
  final reports = MockDataService().getReports();
  
  for (final report in reports) {
    await _mapController?.addSymbol(
      SymbolOptions(
        geometry: LatLng(report.latitude, report.longitude),
        iconImage: 'crime-marker',
        iconSize: 0.5,
      ),
      {'reportId': report.id},
    );
  }
}
```

### 3. Marker Tap Detection
```dart
_mapController?.onSymbolTapped.add((symbol) {
  final reportId = symbol.data?['reportId'];
  print('Tapped marker: $reportId');
  // TODO: Navigate to location feed in Milestone 8
});
```

## Deliverable Checklist
- [ ] Circular markers appear at crime locations
- [ ] Markers show thumbnail images
- [ ] Border color matches crime type
- [ ] Tap on marker logs report ID
- [ ] Markers render efficiently (no lag)

## Files (3 total)
1. `lib/features/map/presentation/map_screen.dart` - Update
2. `lib/features/map/presentation/widgets/crime_marker.dart` - Create
3. `lib/features/map/data/marker_generator.dart` - Create (convert widget to image)