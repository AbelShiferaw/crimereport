# Milestone 5: Mapbox Map – Basic Setup

## Status
Completed

## Goal
Integrate Mapbox Maps Flutter SDK, display an interactive dark-styled map centered on the user's location with a pulsing location puck, permission handling, and a re-center FAB.

## Dependencies
Requires **Milestone 2** complete (mock data available via `MockDataService`).

## What Was Built
A `MapScreen` widget built with Riverpod (`ConsumerStatefulWidget`) that:
- Reads the Mapbox access token from `.env` via `flutter_dotenv`
- Requests location permission through a dedicated `LocationService` abstraction
- Shows loading / permission-denied placeholder screens while resolving state
- Renders a full-bleed `MapWidget` with `MapboxStyles.DARK`
- Configures a pulsing location puck with accuracy ring via the Mapbox location component
- Provides a mini FAB to fly the camera back to the user's position

## Key Files

| File | Description |
|---|---|
| `apps/mobile/lib/features/map/presentation/map_screen.dart` | Main map screen – lifecycle, callbacks, UI |
| `apps/mobile/lib/features/map/providers/map_providers.dart` | `LocationService`, location/permission state providers, `mapReportsProvider` |
| `apps/mobile/lib/core/constants/app_constants.dart` | Map zoom levels, puck radii, timeouts |
| `apps/mobile/lib/shared/widgets/loading_placeholder.dart` | Loading screen shown while fetching location |
| `apps/mobile/lib/shared/widgets/permission_placeholder.dart` | Permission-denied screen with action button |

## Implementation Details

### 1. Mapbox Token Initialization

The token is loaded from the `.env` file at runtime (not compiled-in), keeping secrets out of source control:

```dart
// map_screen.dart – _initMapbox()
void _initMapbox() {
  final mapboxToken = dotenv.env['MAPBOX_ACCESS_TOKEN'] ?? '';
  if (mapboxToken.isNotEmpty) {
    MapboxOptions.setAccessToken(mapboxToken);
  }
}
```

### 2. Location Service Abstraction

Location logic is wrapped in a `LocationService` class for testability. It handles permission checks, position fetching with timeout, and streaming:

```dart
// map_providers.dart
class LocationService {
  Future<LocationPermission> checkPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return LocationPermission.denied;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission;
  }

  Future<Position?> getCurrentPosition() async {
    try {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(AppConstants.locationTimeout);
    } catch (e) {
      return null;
    }
  }
}
```

Three Riverpod state providers track location lifecycle:

```dart
final userLocationProvider = StateProvider<Position?>((ref) => null);
final locationLoadingProvider = StateProvider<bool>((ref) => true);
final locationPermissionProvider = StateProvider<LocationPermission?>((ref) => null);
final locationServiceProvider = Provider<LocationService>((ref) => LocationService());
```

### 3. Permission & Loading States

`MapScreen.build()` checks `locationLoadingProvider` and `locationPermissionProvider` to show the correct placeholder before rendering the map:

```dart
if (isLoading) {
  return Container(
    color: AppColors.background,
    child: const LoadingPlaceholder(message: 'Getting your location...'),
  );
}

if (permission == geo.LocationPermission.denied ||
    permission == geo.LocationPermission.deniedForever) {
  return Container(
    color: AppColors.background,
    child: PermissionPlaceholder(
      icon: Icons.location_off_rounded,
      title: 'Location Access Required',
      description: 'Enable location access to see crime reports near you on the map.',
      buttonLabel: isPermanentlyDenied ? 'Open Settings' : 'Enable Location',
      onButtonPressed: isPermanentlyDenied ? _openLocationSettings : _initLocation,
    ),
  );
}
```

### 4. Map Widget & Dark Style

The map uses `MapboxStyles.DARK` and centers on the user's location (falling back to San Francisco defaults):

```dart
MapWidget(
  key: const ValueKey('mapWidget'),
  styleUri: MapboxStyles.DARK,
  cameraOptions: CameraOptions(
    center: initialCenter,
    zoom: AppConstants.defaultMapZoom,  // 14.0
  ),
  onMapCreated: _onMapCreated,
  onStyleLoadedListener: _onStyleLoaded,
  onCameraChangeListener: _onCameraChanged,
),
```

### 5. Location Puck

A pulsing location puck with an accuracy ring is configured via the Mapbox location component:

```dart
Future<void> _setupLocationPuck() async {
  await _mapboxMap!.location.updateSettings(
    LocationComponentSettings(
      enabled: true,
      pulsingEnabled: true,
      pulsingColor: AppColors.primary.toARGB32(),
      pulsingMaxRadius: AppConstants.locationPuckPulsingRadius,  // 30.0
      showAccuracyRing: true,
      accuracyRingColor: AppColors.primary
          .withAlpha((255 * AppConstants.locationPuckAccuracyAlpha).round())
          .toARGB32(),
      accuracyRingBorderColor: AppColors.primary.toARGB32(),
    ),
  );
}
```

### 6. Re-Center FAB

A mini `FloatingActionButton` in the bottom-right flies the camera back to the user:

```dart
Positioned(
  right: AppSpacing.md,
  bottom: AppConstants.mapFabBottomOffset,  // 100.0
  child: FloatingActionButton(
    onPressed: _centerOnUser,
    backgroundColor: AppColors.surface,
    foregroundColor: AppColors.textPrimary,
    mini: true,
    tooltip: 'Center on my location',
    child: const Icon(Icons.my_location_rounded),
  ),
),
```

The `_centerOnUser` method uses `flyTo` with a 1-second animation:

```dart
Future<void> _centerOnUser() async {
  final position = ref.read(userLocationProvider);
  if (position == null || _mapboxMap == null) return;

  await _mapboxMap!.flyTo(
    CameraOptions(
      center: Point(
        coordinates: Position(position.longitude, position.latitude),
      ),
      zoom: AppConstants.recenterMapZoom,  // 15.0
    ),
    MapAnimationOptions(duration: 1000),
  );
}
```

## Testing
No dedicated unit or widget tests exist for the map screen. Location logic is testable via the `LocationService` abstraction.

## Notes
- The original plan used `Geolocator` directly in the widget and a `MapboxMap` constructor-style API. The actual implementation uses `mapbox_maps_flutter`'s `MapWidget` and delegates location to a `LocationService` behind Riverpod providers.
- The access token is read from `.env` via `flutter_dotenv` rather than being compiled-in through `AppConstants.mapboxToken`.
- Permission denied states show a purpose-built `PermissionPlaceholder` widget (not just a blank screen), including an "Open Settings" action for permanently-denied cases.
- The map screen also serves as the host for marker management (`MapMarkerManager`) and focus pulse (`MapFocusPulse`), which are covered in Milestones 6–7.
