import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import 'package:crimereport/core/constants/app_constants.dart';
import 'package:crimereport/features/feed/data/models/report.dart';
import 'package:crimereport/features/map/services/marker_image_service.dart';
import 'package:crimereport/features/map/presentation/map_constants.dart';

/// Manages map marker images, GeoJSON source, and clustered layers.
///
/// Extracted from [MapScreen] to keep the screen widget focused on
/// lifecycle and UI concerns.
class MapMarkerManager {
  final MapboxMap _mapboxMap;
  final MarkerImageService _imageService;
  final Set<String> _registeredImageIds = {};
  final int _markerSize = AppConstants.mapMarkerSize.toInt();

  MapMarkerManager(this._mapboxMap, {MarkerImageService? imageService})
      : _imageService = imageService ?? MarkerImageService.instance;

  // ----------------------------------------------------------
  // Marker image registration
  // ----------------------------------------------------------

  Future<void> registerMarkerImages(List<Report> reports) async {
    final urls = <String>[];
    final colors = <Color>[];
    for (final report in reports) {
      final url = report.primaryMedia?.thumbnailUrl ?? report.primaryMedia?.url;
      if (url != null) {
        urls.add(url);
        colors.add(report.type.color);
      }
    }
    await _imageService.preloadImages(urls, borderColors: colors);
    await Future.wait(reports.map(_registerSingleImage));
  }

  Future<void> _registerSingleImage(Report report) async {
    final imageId = getImageId(report.id);

    try {
      final imageData = await _getImageData(report);
      if (imageData == null) return;

      await _mapboxMap.style.addStyleImage(
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
    ))
        .data;

    return imageData;
  }

  String getImageId(String reportId) => 'marker-$reportId';

  // ----------------------------------------------------------
  // Clustered source and layers
  // ----------------------------------------------------------

  Future<void> addClusteredSourceAndLayers(List<Report> reports) async {
    try {
      final sourceExists = await _mapboxMap.style.styleSourceExists(
        MapLayerIds.source,
      );
      if (sourceExists) return;

      await _mapboxMap.style.addSource(
        GeoJsonSource(
          id: MapLayerIds.source,
          data: json.encode(buildGeoJson(reports)),
          cluster: true,
          clusterRadius: ClusterConfig.radius,
          clusterMaxZoom: ClusterConfig.maxZoom,
          clusterMinPoints: ClusterConfig.minPoints.toDouble(),
        ),
      );

      await _addClusterCircleLayer();
      await _addClusterCountLayer();
      await _addUnclusteredMarkersLayer();
    } catch (e) {
      debugPrint('Failed to add clustered layers: $e');
    }
  }

  /// Refresh the GeoJSON data in an existing source (e.g. after filter change).
  Future<void> refreshGeoJsonSource(List<Report> reports) async {
    try {
      await _mapboxMap.style.setStyleSourceProperty(
        MapLayerIds.source,
        'data',
        json.encode(buildGeoJson(reports)),
      );
    } catch (e) {
      debugPrint('Failed to refresh map markers: $e');
    }
  }

  Map<String, dynamic> buildGeoJson(List<Report> reports) {
    final features = reports.asMap().entries.map((entry) {
      return _buildGeoJsonFeature(entry.key, entry.value);
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
        'imageId': getImageId(report.id),
        'crimeType': report.type.name,
        'description': report.description,
      },
    };
  }

  Future<void> _addClusterCircleLayer() async {
    final layer = CircleLayer(
      id: MapLayerIds.clusterCircles,
      sourceId: MapLayerIds.source,
      filter: ['has', 'point_count'],
      circleColor: const Color(0xFF0D1B2A).toARGB32(),
      circleRadiusExpression: [
        'step',
        ['get', 'point_count'],
        ClusterConfig.smallCircleRadius,
        10,
        ClusterConfig.mediumCircleRadius,
        50,
        ClusterConfig.largeCircleRadius,
      ],
      circleStrokeWidth: 2.0,
      circleStrokeColor: const Color(0xFF4FD1C5).toARGB32(),
    );

    await _mapboxMap.style.addLayer(layer);
  }

  Future<void> _addClusterCountLayer() async {
    final layer = SymbolLayer(
      id: MapLayerIds.clusterCount,
      sourceId: MapLayerIds.source,
      filter: ['has', 'point_count'],
      textFieldExpression: ['get', 'point_count_abbreviated'],
      textSize: 14.0,
      textColor: Colors.white.toARGB32(),
      textIgnorePlacement: true,
      textAllowOverlap: true,
    );

    await _mapboxMap.style.addLayer(layer);
  }

  Future<void> _addUnclusteredMarkersLayer() async {
    final layer = SymbolLayer(
      id: MapLayerIds.unclusteredMarkers,
      sourceId: MapLayerIds.source,
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
        ZoomScaling.worldView,
        8,
        ZoomScaling.country,
        10,
        ZoomScaling.city,
        12,
        ZoomScaling.neighborhood,
        14,
        ZoomScaling.street,
      ],
      iconAllowOverlap: true,
      iconIgnorePlacement: true,
      iconPitchAlignment: IconPitchAlignment.VIEWPORT,
      iconRotationAlignment: IconRotationAlignment.VIEWPORT,
      iconAnchor: IconAnchor.CENTER,
    );

    await _mapboxMap.style.addLayer(layer);
  }

  // ----------------------------------------------------------
  // Cleanup
  // ----------------------------------------------------------

  Future<void> cleanup() async {
    try {
      _mapboxMap.removeInteraction(MapLayerIds.clusterTapInteraction);
      _mapboxMap.removeInteraction(MapLayerIds.markerTapInteraction);

      for (final layerId in [
        MapLayerIds.unclusteredMarkers,
        MapLayerIds.clusterCount,
        MapLayerIds.clusterCircles,
      ]) {
        if (await _mapboxMap.style.styleLayerExists(layerId)) {
          await _mapboxMap.style.removeStyleLayer(layerId);
        }
      }

      if (await _mapboxMap.style.styleSourceExists(MapLayerIds.source)) {
        await _mapboxMap.style.removeStyleSource(MapLayerIds.source);
      }

      for (final imageId in _registeredImageIds) {
        await _mapboxMap.style.removeStyleImage(imageId);
      }
    } catch (_) {
      // Ignore cleanup errors during dispose
    }
  }
}
