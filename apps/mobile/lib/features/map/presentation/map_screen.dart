import 'dart:async';
import 'dart:convert';
import 'dart:math' show pow;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/theme.dart';
import '../../../core/utils/geo_utils.dart';
import '../../../shared/data/mock_data_service.dart';
import '../../../shared/widgets/loading_placeholder.dart';
import '../../../shared/widgets/permission_placeholder.dart';
import '../../feed/data/models/report.dart';
import '../../feed/providers/feed_providers.dart';
import '../providers/map_providers.dart';
import '../services/marker_image_service.dart';
import 'location_feed_screen.dart';

/// Layer and source IDs for map markers.
class _MapLayerIds {
  static const String source = 'crime-markers-source';
  static const String clusterCircles = 'crime-clusters';
  static const String clusterCount = 'crime-cluster-count';
  static const String unclusteredMarkers = 'crime-unclustered-markers';
  static const String clusterTapInteraction = 'crime-cluster-tap';
  static const String markerTapInteraction = 'crime-marker-tap';

  _MapLayerIds._();
}

/// Clustering configuration constants.
class _ClusterConfig {
  static const double radius = 50.0;
  static const double maxZoom = 12.0;
  static const int minPoints = 2;

  static const double smallCircleRadius = 18.0;
  static const double mediumCircleRadius = 24.0;
  static const double largeCircleRadius = 30.0;

  _ClusterConfig._();
}

/// Zoom-based marker scaling constants.
class _ZoomScaling {
  static const double worldView = 0.1;
  static const double country = 0.2;
  static const double city = 0.4;
  static const double neighborhood = 0.6;
  static const double street = 0.8;

  _ZoomScaling._();
}

/// Focus pulse animation configuration.
class _FocusPulseConfig {
  static const double minRadius = 40.0;
  static const double maxRadius = 70.0;
  static const double maxOpacity = 0.6;
  static const double blur = 0.5;
  static const Duration interval = Duration(milliseconds: 40);
  static const double phaseStep = 0.025;

  /// Minimum zoom level to show focus pulse (past cluster level).
  static const double minZoom = 13.0;

  _FocusPulseConfig._();
}

/// Interactive Mapbox map screen with clustering and focus highlight.
///
/// Features:
/// - Marker clustering at low zoom levels
/// - Zoom-based marker scaling
/// - Focus pulse on closest marker when zoomed in
/// - Tap cluster to expand, tap marker to see details
class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  MapboxMap? _mapboxMap;

  List<Report> _reports = [];
  final _imageService = MarkerImageService.instance;
  final Set<String> _registeredImageIds = {};
  bool _markersAdded = false;
  late final int _markerSize = AppConstants.mapMarkerSize.toInt();

  // Focus pulse animation
  CircleAnnotationManager? _pulseManager;
  CircleAnnotation? _focusPulse;
  String? _focusedReportId;
  Timer? _pulseTimer;
  Timer? _periodicUpdateTimer;
  Timer? _stopDetectionTimer;
  double _pulsePhase = 0.0;
  bool _isPulseVisible = false;

  @override
  void initState() {
    super.initState();
    _initMapbox();
    _initLocation();
    _loadReports();
  }

  @override
  void dispose() {
    _periodicUpdateTimer?.cancel();
    _stopDetectionTimer?.cancel();
    _stopPulseAnimation();
    _cleanup();
    super.dispose();
  }

  void _initMapbox() {
    final mapboxToken = dotenv.env['MAPBOX_ACCESS_TOKEN'] ?? '';
    if (mapboxToken.isNotEmpty) {
      MapboxOptions.setAccessToken(mapboxToken);
    }
  }

  Future<void> _initLocation() async {
    final locationService = ref.read(locationServiceProvider);

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

  void _loadReports() {
    _reports = MockDataService.instance.getReports();
  }

  void _onMapCreated(MapboxMap mapboxMap) async {
    _mapboxMap = mapboxMap;
    _setupLocationPuck();
    await _setupFocusPulseManager();
  }

  void _onCameraChangeListener(CameraChangedEventData data) {
    _onCameraChanged(data);
  }

  void _onStyleLoaded(StyleLoadedEventData data) async {
    if (_markersAdded) return;
    _markersAdded = true;

    await _registerMarkerImages();
    await _addClusteredSourceAndLayers();
    _setupTapInteractions();
  }

  // ============================================================
  // FOCUS PULSE ANIMATION
  // ============================================================

  Future<void> _setupFocusPulseManager() async {
    debugPrint('🎯 Setting up focus pulse manager...');
    _pulseManager = await _mapboxMap!.annotations
        .createCircleAnnotationManager();
    debugPrint('✅ Focus pulse manager created: $_pulseManager');
  }

  void _onCameraChanged(CameraChangedEventData data) {
    // Start periodic updates if not already running
    if (_periodicUpdateTimer == null || !_periodicUpdateTimer!.isActive) {
      // Immediate first update
      _updateFocusPulse();

      // Then update every 300ms while camera is moving
      _periodicUpdateTimer = Timer.periodic(
        const Duration(milliseconds: 300),
        (_) => _updateFocusPulse(),
      );
    }

    // Reset the "camera stopped" detection timer
    _stopDetectionTimer?.cancel();
    _stopDetectionTimer = Timer(const Duration(milliseconds: 400), () {
      // Camera has been idle for 400ms - stop periodic updates
      _periodicUpdateTimer?.cancel();
      _periodicUpdateTimer = null;
      // One final update to ensure accuracy
      _updateFocusPulse();
    });
  }

  Future<void> _updateFocusPulse() async {
    if (_mapboxMap == null || _pulseManager == null) {
      debugPrint('❌ _updateFocusPulse: mapbox or pulseManager is null');
      return;
    }

    try {
      // Get current camera state (includes center and zoom)
      final cameraState = await _mapboxMap!.getCameraState();
      final zoom = cameraState.zoom;
      debugPrint(
        '🔍 Zoom level: $zoom (min required: ${_FocusPulseConfig.minZoom})',
      );

      // Hide pulse if zoomed out (clustered view)
      if (zoom < _FocusPulseConfig.minZoom) {
        debugPrint('⬇️ Zoom too low, hiding pulse');
        await _hideFocusPulse();
        return;
      }

      // Get visible bounds of the map
      final bounds = await _mapboxMap!.coordinateBoundsForCamera(
        CameraOptions(center: cameraState.center, zoom: zoom),
      );

      // Filter to only reports within visible bounds
      final swLat = bounds.southwest.coordinates.lat.toDouble();
      final swLng = bounds.southwest.coordinates.lng.toDouble();
      final neLat = bounds.northeast.coordinates.lat.toDouble();
      final neLng = bounds.northeast.coordinates.lng.toDouble();

      final visibleReports = _reports.where((report) {
        return GeoUtils.isWithinBounds(
          lat: report.latitude,
          lng: report.longitude,
          swLat: swLat,
          swLng: swLng,
          neLat: neLat,
          neLng: neLng,
        );
      }).toList();

      if (visibleReports.isEmpty) {
        debugPrint('❌ No visible reports in bounds');
        await _hideFocusPulse();
        return;
      }

      // Camera center IS the screen center
      final centerCoord = cameraState.center;
      debugPrint(
        '📌 Screen center: ${centerCoord.coordinates.lat}, ${centerCoord.coordinates.lng}',
      );

      // Find closest report among visible ones
      final closest = _findClosestReportFrom(centerCoord, visibleReports);
      if (closest == null) {
        debugPrint('❌ No closest report found');
        await _hideFocusPulse();
        return;
      }
      debugPrint(
        '✅ Closest report: ${closest.id} - ${closest.type.displayName}',
      );

      // Show/move pulse to closest marker
      await _showFocusPulse(closest);
    } catch (e) {
      debugPrint('❌ Error in _updateFocusPulse: $e');
    }
  }

  Report? _findClosestReportFrom(Point center, List<Report> reports) {
    if (reports.isEmpty) return null;

    Report? closest;
    double minDistance = double.infinity;

    final centerLat = center.coordinates.lat.toDouble();
    final centerLng = center.coordinates.lng.toDouble();

    for (final report in reports) {
      final distance = GeoUtils.distanceMeters(
        centerLat,
        centerLng,
        report.latitude,
        report.longitude,
      );
      if (distance < minDistance) {
        minDistance = distance;
        closest = report;
      }
    }

    return closest;
  }

  Future<void> _showFocusPulse(Report report) async {
    if (_pulseManager == null) {
      debugPrint('❌ _showFocusPulse: pulseManager is null');
      return;
    }

    final geometry = Point(
      coordinates: Position(report.longitude, report.latitude),
    );
    final color = report.type.color;

    // If same report, just ensure animation is running
    if (_focusedReportId == report.id && _focusPulse != null) {
      debugPrint('🔄 Same report, ensuring animation running');
      if (_pulseTimer == null) _startPulseAnimation();
      return;
    }

    // Remove old pulse
    if (_focusPulse != null) {
      debugPrint('🗑️ Removing old pulse');
      try {
        await _pulseManager!.delete(_focusPulse!);
      } catch (e) {
        debugPrint('⚠️ Error deleting old pulse: $e');
      }
    }

    // Create new pulse at this location
    try {
      debugPrint(
        '✨ Creating pulse at ${report.latitude}, ${report.longitude} with color ${color.toARGB32().toRadixString(16)}',
      );
      _focusPulse = await _pulseManager!.create(
        CircleAnnotationOptions(
          geometry: geometry,
          circleRadius: _FocusPulseConfig.minRadius,
          circleColor: color.toARGB32(),
          circleOpacity: _FocusPulseConfig.maxOpacity,
          circleBlur: _FocusPulseConfig.blur,
        ),
      );

      _focusedReportId = report.id;
      _isPulseVisible = true;
      debugPrint('✅ Pulse created successfully, starting animation');

      // Start animation
      _startPulseAnimation();
    } catch (e) {
      debugPrint('❌ Failed to create focus pulse: $e');
    }
  }

  Future<void> _hideFocusPulse() async {
    if (!_isPulseVisible) return;

    _stopPulseAnimation();

    if (_focusPulse != null && _pulseManager != null) {
      try {
        await _pulseManager!.delete(_focusPulse!);
      } catch (e) {
        // Ignore deletion errors
      }
      _focusPulse = null;
    }

    _focusedReportId = null;
    _isPulseVisible = false;
  }

  void _startPulseAnimation() {
    if (_pulseTimer != null) return;
    _pulseTimer = Timer.periodic(
      _FocusPulseConfig.interval,
      (_) => _animatePulse(),
    );
  }

  void _stopPulseAnimation() {
    _pulseTimer?.cancel();
    _pulseTimer = null;
    _pulsePhase = 0.0;
  }

  void _animatePulse() {
    if (_focusPulse == null || _pulseManager == null) return;

    // Advance phase
    _pulsePhase = (_pulsePhase + _FocusPulseConfig.phaseStep) % 1.0;

    // Ease-in-out
    final easedPhase = _pulsePhase < 0.5
        ? 2 * _pulsePhase * _pulsePhase
        : 1 - pow(-2 * _pulsePhase + 2, 2) / 2;

    // Calculate animated values
    final radius =
        _FocusPulseConfig.minRadius +
        (_FocusPulseConfig.maxRadius - _FocusPulseConfig.minRadius) *
            easedPhase;
    final opacity = _FocusPulseConfig.maxOpacity * (1.0 - easedPhase * 0.7);

    // Update pulse
    _focusPulse!.circleRadius = radius;
    _focusPulse!.circleOpacity = opacity;
    _pulseManager!.update(_focusPulse!);
  }

  // ============================================================
  // MARKER IMAGES
  // ============================================================

  Future<void> _registerMarkerImages() async {
    if (_mapboxMap == null) return;

    final urls = <String>[];
    final colors = <Color>[];
    for (final report in _reports) {
      final url = report.primaryMedia?.thumbnailUrl ?? report.primaryMedia?.url;
      if (url != null) {
        urls.add(url);
        colors.add(report.type.color);
      }
    }
    await _imageService.preloadImages(urls, borderColors: colors);

    await Future.wait(_reports.map((report) => _registerSingleImage(report)));

    debugPrint('Registered ${_registeredImageIds.length} marker images');
  }

  Future<void> _registerSingleImage(Report report) async {
    final imageId = _getImageId(report.id);

    try {
      final imageData = await _getImageData(report);
      if (imageData == null) return;

      await _mapboxMap!.style.addStyleImage(
        imageId,
        1.0,
        MbxImage(width: _markerSize, height: _markerSize, data: imageData),
        false,
        [],
        [],
        null,
      );

      _registeredImageIds.add(imageId);
    } catch (e) {
      debugPrint('Failed to register image $imageId: $e');
    }
  }

  Future<Uint8List?> _getImageData(Report report) async {
    final thumbnailUrl =
        report.primaryMedia?.thumbnailUrl ?? report.primaryMedia?.url;

    Uint8List? imageData;
    if (thumbnailUrl != null) {
      final result = await _imageService.getMarkerImage(
        thumbnailUrl,
        borderColor: report.type.color,
      );
      imageData = result.data;
    }

    imageData ??= (await _imageService.loadFallbackIcon(
      borderColor: report.type.color,
    )).data;

    return imageData;
  }

  String _getImageId(String reportId) => 'marker-$reportId';

  // ============================================================
  // CLUSTERED LAYERS
  // ============================================================

  Future<void> _addClusteredSourceAndLayers() async {
    if (_mapboxMap == null) return;

    try {
      final sourceExists = await _mapboxMap!.style.styleSourceExists(
        _MapLayerIds.source,
      );
      if (sourceExists) {
        debugPrint('Source already exists, skipping');
        return;
      }

      final geojson = _buildGeoJson();
      await _mapboxMap!.style.addSource(
        GeoJsonSource(
          id: _MapLayerIds.source,
          data: json.encode(geojson),
          cluster: true,
          clusterRadius: _ClusterConfig.radius,
          clusterMaxZoom: _ClusterConfig.maxZoom,
          clusterMinPoints: _ClusterConfig.minPoints.toDouble(),
        ),
      );

      await _addClusterCircleLayer();
      await _addClusterCountLayer();
      await _addUnclusteredMarkersLayer();

      debugPrint('Added clustered source with ${_reports.length} markers');
    } catch (e) {
      debugPrint('Failed to add clustered layers: $e');
    }
  }

  Future<void> _addClusterCircleLayer() async {
    final layer = CircleLayer(
      id: _MapLayerIds.clusterCircles,
      sourceId: _MapLayerIds.source,
      filter: ['has', 'point_count'],
      circleColor: const Color(0xFF0D1B2A).toARGB32(),
      circleRadiusExpression: [
        'step',
        ['get', 'point_count'],
        _ClusterConfig.smallCircleRadius,
        10,
        _ClusterConfig.mediumCircleRadius,
        50,
        _ClusterConfig.largeCircleRadius,
      ],
      circleStrokeWidth: 2.0,
      circleStrokeColor: const Color(0xFF4FD1C5).toARGB32(),
    );

    await _mapboxMap!.style.addLayer(layer);
  }

  Future<void> _addClusterCountLayer() async {
    final layer = SymbolLayer(
      id: _MapLayerIds.clusterCount,
      sourceId: _MapLayerIds.source,
      filter: ['has', 'point_count'],
      textFieldExpression: ['get', 'point_count_abbreviated'],
      textSize: 14.0,
      textColor: Colors.white.toARGB32(),
      textIgnorePlacement: true,
      textAllowOverlap: true,
    );

    await _mapboxMap!.style.addLayer(layer);
  }

  Future<void> _addUnclusteredMarkersLayer() async {
    final layer = SymbolLayer(
      id: _MapLayerIds.unclusteredMarkers,
      sourceId: _MapLayerIds.source,
      filter: [
        '!',
        ['has', 'point_count'],
      ],
      iconImageExpression: ['get', 'imageId'],
      iconSizeExpression: [
        'interpolate',
        ['linear'],
        ['zoom'],
        5,
        _ZoomScaling.worldView,
        8,
        _ZoomScaling.country,
        10,
        _ZoomScaling.city,
        12,
        _ZoomScaling.neighborhood,
        14,
        _ZoomScaling.street,
      ],
      iconAllowOverlap: true,
      iconIgnorePlacement: true,
      iconPitchAlignment: IconPitchAlignment.VIEWPORT,
      iconRotationAlignment: IconRotationAlignment.VIEWPORT,
      iconAnchor: IconAnchor.CENTER,
    );

    await _mapboxMap!.style.addLayer(layer);
  }

  Map<String, dynamic> _buildGeoJson() {
    final features = _reports.asMap().entries.map((entry) {
      final index = entry.key;
      final report = entry.value;
      return _buildGeoJsonFeature(index, report);
    }).toList();

    return {'type': 'FeatureCollection', 'features': features};
  }

  Map<String, dynamic> _buildGeoJsonFeature(int index, Report report) {
    return {
      'type': 'Feature',
      'id': index,
      'geometry': {
        'type': 'Point',
        'coordinates': [report.longitude, report.latitude],
      },
      'properties': {
        'reportId': report.id,
        'imageId': _getImageId(report.id),
        'crimeType': report.type.name,
        'description': report.description,
      },
    };
  }

  // ============================================================
  // TAP INTERACTIONS
  // ============================================================

  void _setupTapInteractions() {
    if (_mapboxMap == null) return;

    final clusterTap = TapInteraction(
      FeaturesetDescriptor(layerId: _MapLayerIds.clusterCircles),
      (feature, context) async {
        await _onClusterTapped(feature);
      },
    );
    _mapboxMap!.addInteraction(
      clusterTap,
      interactionID: _MapLayerIds.clusterTapInteraction,
    );

    final markerTap = TapInteraction(
      FeaturesetDescriptor(layerId: _MapLayerIds.unclusteredMarkers),
      (feature, context) {
        final reportId = feature.properties['reportId'] as String?;
        if (reportId == null) return;

        final report = _reports.firstWhere(
          (r) => r.id == reportId,
          orElse: () => _reports.first,
        );
        _onMarkerTapped(report);
      },
    );
    _mapboxMap!.addInteraction(
      markerTap,
      interactionID: _MapLayerIds.markerTapInteraction,
    );
  }

  Future<void> _onClusterTapped(
    TypedFeaturesetFeature<FeaturesetDescriptor> feature,
  ) async {
    try {
      final properties = feature.properties;
      final geometry = feature.geometry;

      if (geometry.isEmpty) {
        debugPrint('Invalid cluster feature data');
        return;
      }

      final clusterId = properties['cluster_id'];
      if (clusterId == null) {
        debugPrint('Missing cluster_id in properties');
        return;
      }

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
        _MapLayerIds.source,
        clusterFeature,
      );

      final coordinates = geometry['coordinates'] as List?;
      if (coordinates == null || coordinates.length < 2) {
        debugPrint('Invalid coordinates in cluster geometry');
        return;
      }

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
    debugPrint('Marker tapped: ${report.type.displayName}');

    // Start preloading videos BEFORE navigating for faster load times
    final reports = MockDataService.instance.getNearbyReports(
      report.latitude,
      report.longitude,
      AppConstants.locationFeedRadiusKm,
    );

    // Reorder so tapped report is first (same logic as provider)
    final reordered = reports.where((r) => r.id != report.id).toList();
    reordered.insert(0, report);

    // Start preloading immediately
    ref.read(videoPreloadManagerProvider).preloadAround(reordered, 0);

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => LocationFeedScreen(initialReport: report),
      ),
    );
  }

  // ============================================================
  // CLEANUP & LOCATION
  // ============================================================

  Future<void> _cleanup() async {
    if (_mapboxMap == null) return;

    try {
      _mapboxMap!.removeInteraction(_MapLayerIds.clusterTapInteraction);
      _mapboxMap!.removeInteraction(_MapLayerIds.markerTapInteraction);

      for (final layerId in [
        _MapLayerIds.unclusteredMarkers,
        _MapLayerIds.clusterCount,
        _MapLayerIds.clusterCircles,
      ]) {
        if (await _mapboxMap!.style.styleLayerExists(layerId)) {
          await _mapboxMap!.style.removeStyleLayer(layerId);
        }
      }

      if (await _mapboxMap!.style.styleSourceExists(_MapLayerIds.source)) {
        await _mapboxMap!.style.removeStyleSource(_MapLayerIds.source);
      }

      for (final imageId in _registeredImageIds) {
        await _mapboxMap!.style.removeStyleImage(imageId);
      }
    } catch (e) {
      // Ignore cleanup errors
    }
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

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final isLoading = ref.watch(locationLoadingProvider);
    final permission = ref.watch(locationPermissionProvider);
    final userPosition = ref.watch(userLocationProvider);

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
          buttonLabel: isPermanentlyDenied
              ? 'Open Settings'
              : 'Enable Location',
          onButtonPressed: isPermanentlyDenied
              ? _openLocationSettings
              : _initLocation,
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
            onCameraChangeListener: _onCameraChangeListener,
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
