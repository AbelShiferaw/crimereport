# Milestone 7: Mapbox Map – Clustering

## Status
Completed

## Goal
Implement marker clustering so nearby crime markers group into styled cluster circles when zoomed out, with count badges and tap-to-expand behavior. Additionally, add a focus pulse animation that highlights the closest marker to screen center when zoomed in.

## Dependencies
Requires **Milestone 6** complete (markers displaying via `MapMarkerManager`).

## What Was Built
1. **Clustering** — A `GeoJsonSource` with `cluster: true` feeds three layers (cluster circles, count labels, unclustered markers). Tapping a cluster flies the camera to its expansion zoom.
2. **Focus Pulse** — A `MapFocusPulse` class that draws a pulsing `CircleAnnotation` around the nearest marker when zoomed past the cluster level (zoom ≥ 13). The pulse uses eased animation and hides during zoomed-out / no-marker states.

## Key Files

| File | Description |
|---|---|
| `apps/mobile/lib/features/map/presentation/map_marker_manager.dart` | `addClusteredSourceAndLayers()`, cluster/count/unclustered layer setup |
| `apps/mobile/lib/features/map/presentation/map_constants.dart` | `ClusterConfig`, `ZoomScaling`, `FocusPulseConfig`, `MapLayerIds` |
| `apps/mobile/lib/features/map/presentation/map_focus_pulse.dart` | Pulsing circle annotation targeting nearest visible marker |
| `apps/mobile/lib/features/map/presentation/map_screen.dart` | Wires clustering + pulse into map lifecycle |

## Implementation Details

### 1. Cluster Configuration Constants

```dart
// map_constants.dart
class ClusterConfig {
  static const double radius = 50.0;
  static const double maxZoom = 12.0;
  static const int minPoints = 2;

  static const double smallCircleRadius = 18.0;
  static const double mediumCircleRadius = 24.0;
  static const double largeCircleRadius = 30.0;
}
```

### 2. GeoJSON Source with Clustering

`MapMarkerManager.addClusteredSourceAndLayers` creates one source that powers all three layers:

```dart
// map_marker_manager.dart
Future<void> addClusteredSourceAndLayers(List<Report> reports) async {
  final sourceExists = await _mapboxMap.style.styleSourceExists(MapLayerIds.source);
  if (sourceExists) return;

  await _mapboxMap.style.addSource(
    GeoJsonSource(
      id: MapLayerIds.source,                        // 'crime-markers-source'
      data: json.encode(buildGeoJson(reports)),
      cluster: true,
      clusterRadius: ClusterConfig.radius,           // 50
      clusterMaxZoom: ClusterConfig.maxZoom,         // 12
      clusterMinPoints: ClusterConfig.minPoints.toDouble(),  // 2
    ),
  );

  await _addClusterCircleLayer();
  await _addClusterCountLayer();
  await _addUnclusteredMarkersLayer();
}
```

### 3. Cluster Circle Layer

Dark navy circles (`#0D1B2A`) with a teal stroke, sized by point count via a `step` expression:

```dart
Future<void> _addClusterCircleLayer() async {
  final layer = CircleLayer(
    id: MapLayerIds.clusterCircles,        // 'crime-clusters'
    sourceId: MapLayerIds.source,
    filter: ['has', 'point_count'],
    circleColor: const Color(0xFF0D1B2A).toARGB32(),
    circleRadiusExpression: [
      'step',
      ['get', 'point_count'],
      ClusterConfig.smallCircleRadius,     // 18  (2–9 points)
      10, ClusterConfig.mediumCircleRadius,// 24  (10–49 points)
      50, ClusterConfig.largeCircleRadius, // 30  (50+ points)
    ],
    circleStrokeWidth: 2.0,
    circleStrokeColor: const Color(0xFF4FD1C5).toARGB32(),
  );
  await _mapboxMap.style.addLayer(layer);
}
```

### 4. Cluster Count Label Layer

White text showing abbreviated counts, placed on top of the circles:

```dart
Future<void> _addClusterCountLayer() async {
  final layer = SymbolLayer(
    id: MapLayerIds.clusterCount,          // 'crime-cluster-count'
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
```

### 5. Cluster Tap → Expansion Zoom

Tapping a cluster queries the source for its expansion zoom, then flies the camera there:

```dart
// map_screen.dart
Future<void> _onClusterTapped(
  TypedFeaturesetFeature<FeaturesetDescriptor> feature,
) async {
  final clusterId = feature.properties['cluster_id'];
  if (clusterId == null) return;

  final clusterFeature = {
    'type': 'Feature',
    'id': clusterId,
    'properties': feature.properties,
    'geometry': {
      'type': feature.geometry['type'],
      'coordinates': feature.geometry['coordinates'],
    },
  };

  final result = await _mapboxMap!.getGeoJsonClusterExpansionZoom(
    MapLayerIds.source,
    clusterFeature,
  );

  final expansionZoom = (result.value != null)
      ? double.tryParse(result.value.toString()) ?? 14.0
      : 14.0;

  await _mapboxMap!.flyTo(
    CameraOptions(
      center: Point(coordinates: Position(lng, lat)),
      zoom: expansionZoom + 0.5,
    ),
    MapAnimationOptions(duration: 500),
  );
}
```

### 6. Tap Interaction Registration

Both cluster and marker taps are registered via `TapInteraction` after layers are added:

```dart
// map_screen.dart – _setupTapInteractions()
final clusterTap = TapInteraction(
  FeaturesetDescriptor(layerId: MapLayerIds.clusterCircles),
  (feature, context) async => await _onClusterTapped(feature),
);
_mapboxMap!.addInteraction(clusterTap, interactionID: MapLayerIds.clusterTapInteraction);

final markerTap = TapInteraction(
  FeaturesetDescriptor(layerId: MapLayerIds.unclusteredMarkers),
  (feature, context) { /* navigate to location feed */ },
);
_mapboxMap!.addInteraction(markerTap, interactionID: MapLayerIds.markerTapInteraction);
```

### 7. Dynamic Source Refresh

When crime-type filters change, the GeoJSON source is updated in-place without re-creating layers:

```dart
// map_marker_manager.dart
Future<void> refreshGeoJsonSource(List<Report> reports) async {
  await _mapboxMap.style.setStyleSourceProperty(
    MapLayerIds.source,
    'data',
    json.encode(buildGeoJson(reports)),
  );
}

// map_screen.dart – wired via ref.listen
ref.listen<List<Report>>(mapReportsProvider, (previous, next) {
  _reports = next;
  _focusPulse?.reports = next;
  if (_markersAdded) {
    _markerManager?.refreshGeoJsonSource(next);
  }
});
```

### 8. Focus Pulse Animation

`MapFocusPulse` adds a pulsing `CircleAnnotation` on the nearest visible marker when zoom ≥ 13:

```dart
// map_focus_pulse.dart
class MapFocusPulse {
  final MapboxMap _mapboxMap;
  CircleAnnotationManager? _pulseManager;
  CircleAnnotation? _focusPulse;

  Future<void> _showPulse(Report report) async {
    _focusPulse = await _pulseManager!.create(
      CircleAnnotationOptions(
        geometry: Point(coordinates: Position(report.longitude, report.latitude)),
        circleRadius: FocusPulseConfig.minRadius,  // 40
        circleColor: report.type.color.toARGB32(),
        circleOpacity: FocusPulseConfig.maxOpacity, // 0.6
        circleBlur: FocusPulseConfig.blur,          // 0.5
      ),
    );
    _startAnimation();
  }
}
```

The animation uses an eased sine curve (quadratic in/out), oscillating radius between 40–70 px and fading opacity:

```dart
Future<void> _animatePulse() async {
  _pulsePhase = (_pulsePhase + FocusPulseConfig.phaseStep) % 1.0;  // 0.025

  final easedPhase = _pulsePhase < 0.5
      ? 2 * _pulsePhase * _pulsePhase
      : 1 - pow(-2 * _pulsePhase + 2, 2) / 2;

  final radius = FocusPulseConfig.minRadius +
      (FocusPulseConfig.maxRadius - FocusPulseConfig.minRadius) * easedPhase;
  final opacity = FocusPulseConfig.maxOpacity * (1.0 - easedPhase * 0.7);

  _focusPulse!.circleRadius = radius;
  _focusPulse!.circleOpacity = opacity;
  await _pulseManager!.update(_focusPulse!);
}
```

### Visual Design Summary

| Cluster Size | Circle Radius | Fill | Stroke |
|---|---|---|---|
| 2–9 | 18 px | `#0D1B2A` (navy) | `#4FD1C5` (teal), 2 px |
| 10–49 | 24 px | same | same |
| 50+ | 30 px | same | same |

### 9. Cleanup

`MapMarkerManager.cleanup()` removes interactions, layers, source, and registered images on dispose:

```dart
Future<void> cleanup() async {
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
}
```

## Testing
No dedicated unit or widget tests for clustering or focus pulse. All clustering behavior relies on Mapbox's native implementation; the focus pulse uses standard `CircleAnnotationManager` APIs.

## Notes
- The original plan used `mapbox_gl` style APIs (`addSource`, `addLayer` with property maps). The actual implementation uses `mapbox_maps_flutter`'s typed classes (`GeoJsonSource`, `CircleLayer`, `SymbolLayer`).
- Cluster colors are dark navy with teal stroke (not solid red as planned) — matches the app's dark theme.
- The focus pulse was not in the original plan — it was added to provide visual feedback about which marker is "focused" when zoomed in.
- `getGeoJsonClusterExpansionZoom` is used for precise tap-to-expand (the plan used a fixed `zoom + 2` approach).
- Camera change events are throttled (300 ms periodic + 400 ms stop detection) to avoid expensive bounds queries on every frame.
