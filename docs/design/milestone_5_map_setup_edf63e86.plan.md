---
name: Milestone 5 Map Setup
overview: Integrate Mapbox GL Flutter, display an interactive map centered on user location with basic controls (zoom, pan, location tracking).
todos:
  - id: m5-token
    content: Configure Mapbox access token
    status: pending
  - id: m5-permissions
    content: Set up iOS/Android location permissions
    status: pending
  - id: m5-map
    content: Implement MapScreen with Mapbox widget
    status: pending
  - id: m5-location
    content: Add user location tracking
    status: pending
  - id: m5-verify
    content: Test map displays and responds to gestures
    status: pending
---

# Milestone 5: Mapbox Map - Basic Setup

## Goal
Get Mapbox GL working with user location display and basic map interactions.

## Dependencies
Requires **Milestone 2** complete (mock data available).

## Implementation

### 1. Mapbox Setup
- Add Mapbox access token to app
- Configure iOS/Android permissions for location
- Initialize MapboxMap widget

### 2. Map Screen

```dart
// lib/features/map/presentation/map_screen.dart
class MapScreen extends StatefulWidget {
  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  MapboxMapController? _mapController;
  Position? _userPosition;
  
  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
  }
  
  Future<void> _getCurrentLocation() async {
    final permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied) return;
    
    final position = await Geolocator.getCurrentPosition();
    setState(() => _userPosition = position);
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _userPosition == null
          ? Center(child: CircularProgressIndicator())
          : MapboxMap(
              accessToken: AppConstants.mapboxToken,
              initialCameraPosition: CameraPosition(
                target: LatLng(_userPosition!.latitude, _userPosition!.longitude),
                zoom: 14.0,
              ),
              onMapCreated: (controller) => _mapController = controller,
              myLocationEnabled: true,
              myLocationTrackingMode: MyLocationTrackingMode.Tracking,
              styleString: MapboxStyles.DARK,
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _centerOnUser,
        child: Icon(Icons.my_location),
      ),
    );
  }
}
```

### 3. Platform Configuration

**iOS** (`ios/Runner/Info.plist`):
```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>ReportCrime needs your location to show nearby crime reports</string>
<key>MGLMapboxAccessToken</key>
<string>YOUR_TOKEN</string>
```

**Android** (`android/app/src/main/AndroidManifest.xml`):
```xml
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
```

## Deliverable Checklist
- [ ] Mapbox displays with dark style
- [ ] Map centers on user location
- [ ] User location dot visible
- [ ] Can pan and zoom
- [ ] Recenter button works
- [ ] Location permission handled gracefully

## Files (3 total)
1. `lib/features/map/presentation/map_screen.dart` - Update
2. `lib/core/constants/app_constants.dart` - Add Mapbox token
3. Platform config files (Info.plist, AndroidManifest.xml)