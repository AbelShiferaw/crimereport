import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/theme.dart';
import '../../../shared/widgets/loading_placeholder.dart';
import '../../../shared/widgets/permission_placeholder.dart';
import '../providers/map_providers.dart';

/// Interactive Mapbox map screen with user location.
class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  MapboxMap? _mapboxMap;

  @override
  void initState() {
    super.initState();
    _initMapbox();
    _initLocation();
  }

  /// Initialize Mapbox with access token.
  void _initMapbox() {
    final mapboxToken = dotenv.env['MAPBOX_ACCESS_TOKEN'] ?? '';
    if (mapboxToken.isNotEmpty) {
      MapboxOptions.setAccessToken(mapboxToken);
    }
  }

  Future<void> _initLocation() async {
    final locationService = ref.read(locationServiceProvider);

    // Check permission
    final permission = await locationService.checkPermission();
    ref.read(locationPermissionProvider.notifier).state = permission;

    if (permission == geo.LocationPermission.denied ||
        permission == geo.LocationPermission.deniedForever) {
      ref.read(locationLoadingProvider.notifier).state = false;
      return;
    }

    // Get current position
    final position = await locationService.getCurrentPosition();
    if (position != null) {
      ref.read(userLocationProvider.notifier).state = position;
    }

    ref.read(locationLoadingProvider.notifier).state = false;
  }

  void _onMapCreated(MapboxMap mapboxMap) {
    _mapboxMap = mapboxMap;
    _setupLocationPuck();
  }

  Future<void> _setupLocationPuck() async {
    if (_mapboxMap == null) return;

    await _mapboxMap!.location.updateSettings(
      LocationComponentSettings(
        enabled: true,
        pulsingEnabled: true,
        pulsingColor: AppColors.primary.toARGB32(),
        pulsingMaxRadius: AppConstants.locationPuckPulsingRadius,
        showAccuracyRing: true,
        accuracyRingColor: AppColors.primary
            .withAlpha((255 * AppConstants.locationPuckAccuracyAlpha).round())
            .toARGB32(),
        accuracyRingBorderColor: AppColors.primary.toARGB32(),
      ),
    );
  }

  Future<void> _centerOnUser() async {
    final position = ref.read(userLocationProvider);
    if (position == null || _mapboxMap == null) return;

    await _mapboxMap!.flyTo(
      CameraOptions(
        center: Point(
          coordinates: Position(position.longitude, position.latitude),
        ),
        zoom: AppConstants.recenterMapZoom,
      ),
      MapAnimationOptions(duration: 1000),
    );
  }

  Future<void> _openLocationSettings() async {
    final locationService = ref.read(locationServiceProvider);
    await locationService.openSettings();
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = ref.watch(locationLoadingProvider);
    final permission = ref.watch(locationPermissionProvider);
    final userPosition = ref.watch(userLocationProvider);

    // Loading state - uses shared widget
    if (isLoading) {
      return Container(
        color: AppColors.background,
        child: const LoadingPlaceholder(
          message: 'Getting your location...',
        ),
      );
    }

    // Permission denied state - uses shared widget
    if (permission == geo.LocationPermission.denied ||
        permission == geo.LocationPermission.deniedForever) {
      final isPermanentlyDenied =
          permission == geo.LocationPermission.deniedForever;

      return Container(
        color: AppColors.background,
        child: PermissionPlaceholder(
          icon: Icons.location_off_rounded,
          title: 'Location Access Required',
          description:
              'Enable location access to see crime reports near you on the map.',
          buttonLabel:
              isPermanentlyDenied ? 'Open Settings' : 'Enable Location',
          onButtonPressed:
              isPermanentlyDenied ? _openLocationSettings : _initLocation,
        ),
      );
    }

    // Determine initial camera position
    final initialCenter = userPosition != null
        ? Point(
            coordinates:
                Position(userPosition.longitude, userPosition.latitude),
          )
        : Point(
            coordinates: Position(
              AppConstants.defaultLongitude,
              AppConstants.defaultLatitude,
            ),
          );

    // Return just Stack (no Scaffold) so map extends edge-to-edge
    return Stack(
      children: [
        // Mapbox Map - fills entire screen
        Positioned.fill(
          child: MapWidget(
            key: const ValueKey('mapWidget'),
            styleUri: MapboxStyles.DARK,
            cameraOptions: CameraOptions(
              center: initialCenter,
              zoom: AppConstants.defaultMapZoom,
            ),
            onMapCreated: _onMapCreated,
          ),
        ),

        // Recenter FAB
        Positioned(
          right: 16,
          bottom: AppConstants.mapFabBottomOffset,
          child: FloatingActionButton(
            onPressed: _centerOnUser,
            backgroundColor: AppColors.surface,
            foregroundColor: AppColors.textPrimary,
            mini: true,
            tooltip: 'Center on my location',
            child: const Icon(Icons.my_location_rounded),
          ),
        ),
      ],
    );
  }
}
