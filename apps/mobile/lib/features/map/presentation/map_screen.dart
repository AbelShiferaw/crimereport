import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import 'package:crimereport/core/constants/app_constants.dart';
import 'package:crimereport/core/theme/theme.dart';
import 'package:crimereport/shared/widgets/loading_placeholder.dart';
import 'package:crimereport/shared/widgets/permission_placeholder.dart';
import 'package:crimereport/features/feed/data/models/report.dart';
import 'package:crimereport/features/feed/providers/feed_providers.dart';
import 'package:crimereport/features/map/providers/map_providers.dart';
import 'package:crimereport/features/map/presentation/location_feed_screen.dart';
import 'package:crimereport/features/map/presentation/map_constants.dart';
import 'package:crimereport/features/map/presentation/map_focus_pulse.dart';
import 'package:crimereport/features/map/presentation/map_marker_manager.dart';

/// Interactive Mapbox map screen with clustering and focus highlight.
///
/// Delegates marker management to [MapMarkerManager] and pulse animation
/// to [MapFocusPulse] to keep this widget focused on lifecycle and UI.
class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  MapboxMap? _mapboxMap;
  MapMarkerManager? _markerManager;
  MapFocusPulse? _focusPulse;

  List<Report> _reports = [];
  bool _markersAdded = false;
  bool _imagesRegistered = false;

  @override
  void initState() {
    super.initState();
    _initMapbox();
    _initLocation();
  }

  @override
  void dispose() {
    _focusPulse?.dispose();
    _markerManager?.cleanup();
    super.dispose();
  }

  void _initMapbox() {
    final mapboxToken = dotenv.env['MAPBOX_ACCESS_TOKEN'] ?? '';
    if (mapboxToken.isNotEmpty) {
      MapboxOptions.setAccessToken(mapboxToken);
    }
  }

  // ----------------------------------------------------------
  // Location
  // ----------------------------------------------------------

  Future<void> _initLocation() async {
    final locationService = ref.read(locationServiceProvider);
    ref.read(locationLoadingProvider.notifier).state = true;

    final permission = await locationService.checkPermission();
    ref.read(locationPermissionProvider.notifier).state = permission;

    if (permission == geo.LocationPermission.denied ||
        permission == geo.LocationPermission.deniedForever) {
      ref.read(locationLoadingProvider.notifier).state = false;
      return;
    }

    final position = await locationService.getCurrentPosition();
    if (position != null) {
      ref.read(userLocationProvider.notifier).state = position;
    }

    ref.read(locationLoadingProvider.notifier).state = false;
  }

  Future<void> _openLocationSettings() async {
    final locationService = ref.read(locationServiceProvider);
    await locationService.openSettings();
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

  // ----------------------------------------------------------
  // Map callbacks
  // ----------------------------------------------------------

  void _onMapCreated(MapboxMap mapboxMap) async {
    _mapboxMap = mapboxMap;
    _markerManager = MapMarkerManager(mapboxMap);
    _focusPulse = MapFocusPulse(mapboxMap)..reports = _reports;

    _setupLocationPuck();
    await _focusPulse!.setup();
  }

  void _onStyleLoaded(StyleLoadedEventData data) async {
    if (_markersAdded || _markerManager == null) return;
    _markersAdded = true;

    if (!_imagesRegistered) {
      _imagesRegistered = true;
      await _markerManager!.registerMarkerImages(_reports);
    }
    await _markerManager!.addClusteredSourceAndLayers(_reports);
    _setupTapInteractions();
  }

  void _onCameraChanged(CameraChangedEventData data) {
    _focusPulse?.onCameraChanged(data);
  }

  // ----------------------------------------------------------
  // Tap interactions
  // ----------------------------------------------------------

  void _setupTapInteractions() {
    if (_mapboxMap == null) return;

    final clusterTap = TapInteraction(
      FeaturesetDescriptor(layerId: MapLayerIds.clusterCircles),
      (feature, context) async {
        await _onClusterTapped(feature);
      },
    );
    _mapboxMap!.addInteraction(
      clusterTap,
      interactionID: MapLayerIds.clusterTapInteraction,
    );

    final markerTap = TapInteraction(
      FeaturesetDescriptor(layerId: MapLayerIds.unclusteredMarkers),
      (feature, context) {
        final reportId = feature.properties['reportId'] as String?;
        if (reportId == null) return;

        try {
          final report = _reports.firstWhere((r) => r.id == reportId);
          _onMarkerTapped(report);
        } on StateError {
          // Report not in list (e.g. filtered out)
        }
      },
    );
    _mapboxMap!.addInteraction(
      markerTap,
      interactionID: MapLayerIds.markerTapInteraction,
    );
  }

  Future<void> _onClusterTapped(
    TypedFeaturesetFeature<FeaturesetDescriptor> feature,
  ) async {
    try {
      final properties = feature.properties;
      final geometry = feature.geometry;

      if (geometry.isEmpty) return;

      final clusterId = properties['cluster_id'];
      if (clusterId == null) return;

      final clusterFeature = {
        'type': 'Feature',
        'id': clusterId,
        'properties': properties,
        'geometry': {
          'type': geometry['type'],
          'coordinates': geometry['coordinates'],
        },
      };

      final result = await _mapboxMap!.getGeoJsonClusterExpansionZoom(
        MapLayerIds.source,
        clusterFeature,
      );

      final coordinates = geometry['coordinates'] as List?;
      if (coordinates == null || coordinates.length < 2) return;

      final expansionZoom = (result.value != null)
          ? double.tryParse(result.value.toString()) ?? 14.0
          : 14.0;

      await _mapboxMap!.flyTo(
        CameraOptions(
          center: Point(
            coordinates: Position(
              (coordinates[0] as num).toDouble(),
              (coordinates[1] as num).toDouble(),
            ),
          ),
          zoom: expansionZoom + 0.5,
        ),
        MapAnimationOptions(duration: 500),
      );
    } catch (e) {
      debugPrint('Failed to expand cluster: $e');
    }
  }

  void _onMarkerTapped(Report report) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => LocationFeedScreen(initialReport: report),
      ),
    );
  }

  // ----------------------------------------------------------
  // Location puck
  // ----------------------------------------------------------

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

  // ----------------------------------------------------------
  // Build
  // ----------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final isLoading = ref.watch(locationLoadingProvider);
    final permission = ref.watch(locationPermissionProvider);
    final userPosition = ref.watch(userLocationProvider);
    final mapReportsAsync = ref.watch(mapReportsProvider);

    // When map reports resolve, update our local list and refresh markers.
    ref.listen(mapReportsProvider, (previous, next) {
      next.whenData((reports) {
        _reports = reports;
        _focusPulse?.reports = reports;
        if (_markersAdded) {
          if (!_imagesRegistered) {
            _imagesRegistered = true;
            _markerManager?.registerMarkerImages(reports);
          }
          _markerManager?.refreshGeoJsonSource(reports);
        }
      });
    });

    // Seed _reports from the current value on first build.
    mapReportsAsync.whenData((reports) {
      if (_reports.isEmpty && reports.isNotEmpty) {
        _reports = reports;
      }
    });

    if (isLoading) {
      return Container(
        color: AppColors.background,
        child: const LoadingPlaceholder(message: 'Getting your location...'),
      );
    }

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

    final initialCenter = userPosition != null
        ? Point(
            coordinates: Position(
              userPosition.longitude,
              userPosition.latitude,
            ),
          )
        : Point(
            coordinates: Position(
              AppConstants.defaultLongitude,
              AppConstants.defaultLatitude,
            ),
          );

    return Stack(
      children: [
        Positioned.fill(
          child: MapWidget(
            key: const ValueKey('mapWidget'),
            styleUri: MapboxStyles.DARK,
            cameraOptions: CameraOptions(
              center: initialCenter,
              zoom: AppConstants.defaultMapZoom,
            ),
            onMapCreated: _onMapCreated,
            onStyleLoadedListener: _onStyleLoaded,
            onCameraChangeListener: _onCameraChanged,
          ),
        ),
        Positioned(
          right: AppSpacing.md,
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
