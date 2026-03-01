# Milestone 6: Mapbox Map – Crime Markers

## Status
Completed

## Goal
Display per-report image markers on the map — rounded-square thumbnails with crime-type-colored borders — and handle marker taps to navigate to a location feed.

## Dependencies
Requires **Milestone 5** complete (map displaying with location puck).

## What Was Built
Two main classes extracted from `MapScreen`:
1. **`MapMarkerManager`** – registers per-report style images on the Mapbox style, builds GeoJSON, and manages clustered source + layers.
2. **`MarkerImageService`** – downloads thumbnails, crops them to rounded squares with colored borders in a background isolate, and caches results (LRU in-memory + disk via `flutter_cache_manager`).

Each report gets its own Mapbox style image (keyed `marker-{reportId}`) so the unclustered-markers `SymbolLayer` can resolve the correct icon per feature via a `['get', 'imageId']` expression.

## Key Files

| File | Description |
|---|---|
| `apps/mobile/lib/features/map/presentation/map_marker_manager.dart` | Registers images, builds GeoJSON, adds clustered source & layers, refreshes data |
| `apps/mobile/lib/features/map/services/marker_image_service.dart` | Downloads, crops, borders, caches marker images; fallback generation |
| `apps/mobile/lib/features/map/presentation/map_screen.dart` | Orchestrates marker manager lifecycle and tap interactions |
| `apps/mobile/lib/features/map/presentation/map_constants.dart` | `MapLayerIds`, `ClusterConfig`, `ZoomScaling` constants |
| `apps/mobile/lib/core/constants/app_constants.dart` | `mapMarkerSize` (72), `mapMarkerBorderWidth` (4) |

## Implementation Details

### 1. Marker Image Registration

On style load, `MapScreen` tells the marker manager to register images for **all** reports (unfiltered) so that toggling filters never results in missing images:

```dart
// map_screen.dart – _onStyleLoaded()
void _onStyleLoaded(StyleLoadedEventData data) async {
  if (_markersAdded || _markerManager == null) return;
  _markersAdded = true;

  final allReports = MockDataService.instance.getReports();
  await _markerManager!.registerMarkerImages(allReports);
  await _markerManager!.addClusteredSourceAndLayers(_reports);
  _setupTapInteractions();
}
```

`MapMarkerManager.registerMarkerImages` first bulk-preloads all thumbnail URLs in parallel, then registers each image on the Mapbox style:

```dart
// map_marker_manager.dart
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
  final imageId = getImageId(report.id);  // 'marker-{id}'
  final imageData = await _getImageData(report);
  if (imageData == null) return;

  await _mapboxMap.style.addStyleImage(
    imageId, 1.0,
    MbxImage(width: _markerSize, height: _markerSize, data: imageData),
    false, [], [], null,
  );
  _registeredImageIds.add(imageId);
}
```

### 2. Image Processing (Rounded Square + Border)

`MarkerImageService` downloads via `flutter_cache_manager`, then processes in a background isolate:

```dart
// marker_image_service.dart
Future<MarkerImageResult> getMarkerImage(
  String url, {
  Color borderColor = const Color(0xFFFFFFFF),
}) async {
  final cacheKey = '${url}_${borderColor.toARGB32()}';
  final cached = _processedCache.get(cacheKey);
  if (cached != null) return MarkerImageResult.success(cached);

  final file = await _cacheManager
      .getSingleFile(url)
      .timeout(_timeout, onTimeout: () {
    throw TimeoutException('Network timeout loading marker image');
  });
  final bytes = await file.readAsBytes();

  final processed = await compute(_processRoundedSquareMarker, _MarkerProcessParams(
    bytes: bytes,
    borderColorValue: borderColor.toARGB32(),
    size: AppConstants.mapMarkerSize.toInt(),
    borderWidth: AppConstants.mapMarkerBorderWidth.toInt(),
  ));

  _processedCache.put(cacheKey, processed);
  return MarkerImageResult.success(processed);
}
```

The isolate function center-crops the source to a square, resizes to `innerSize`, draws the border as a filled rounded rectangle, then composites the photo inside:

```dart
static Uint8List? _processRoundedSquareMarker(_MarkerProcessParams params) {
  final decoded = img.decodeImage(params.bytes);
  if (decoded == null) return null;

  final size = params.size;
  final borderWidth = params.borderWidth;
  final innerSize = size - (borderWidth * 2);

  // Center-crop to square, resize to innerSize
  final cropped = img.copyCrop(decoded, ...);
  final resized = img.copyResize(cropped, width: innerSize, height: innerSize);

  // Create transparent output, draw border rounded rect, composite photo
  final output = img.Image(width: size, height: size);
  _fillRoundedRect(output, 0, 0, size, size, outerCornerRadius, borderColorImg);

  for (int y = 0; y < innerSize; y++) {
    for (int x = 0; x < innerSize; x++) {
      if (_isInsideRoundedRect(x, y, innerSize, innerSize, innerCornerRadius)) {
        output.setPixel(x + borderWidth, y + borderWidth, resized.getPixel(x, y));
      }
    }
  }

  return Uint8List.fromList(img.encodePng(output));
}
```

When the thumbnail fails to load, a programmatically generated fallback marker is used (dark square with colored border and small center dot).

### 3. Crime-Type Border Colors

Each `ReportType` has a `.color` property. The border color is passed through the entire pipeline — preload, `getMarkerImage`, and the isolate — so markers on the map are visually distinguishable by crime type.

### 4. GeoJSON Feature Structure

Each report maps to a GeoJSON feature with properties that the symbol layer uses:

```dart
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
      'imageId': getImageId(report.id),  // 'marker-{id}'
      'crimeType': report.type.name,
      'description': report.description,
    },
  };
}
```

### 5. Unclustered Markers Layer

Individual markers are rendered via a `SymbolLayer` that reads the `imageId` from feature properties and scales based on zoom:

```dart
final layer = SymbolLayer(
  id: MapLayerIds.unclusteredMarkers,
  sourceId: MapLayerIds.source,
  filter: ['!', ['has', 'point_count']],
  iconImageExpression: ['get', 'imageId'],
  iconSizeExpression: [
    'interpolate', ['linear'], ['zoom'],
    5,  ZoomScaling.worldView,   // 0.1
    8,  ZoomScaling.country,     // 0.2
    10, ZoomScaling.city,        // 0.4
    12, ZoomScaling.neighborhood,// 0.6
    14, ZoomScaling.street,      // 0.8
  ],
  iconAllowOverlap: true,
  iconIgnorePlacement: true,
);
```

### 6. Marker Tap Handling

Taps are registered via `TapInteraction` on the unclustered markers layer. The handler finds the report and navigates to the location feed:

```dart
final markerTap = TapInteraction(
  FeaturesetDescriptor(layerId: MapLayerIds.unclusteredMarkers),
  (feature, context) {
    final reportId = feature.properties['reportId'] as String?;
    if (reportId == null) return;
    try {
      final report = _reports.firstWhere((r) => r.id == reportId);
      _onMarkerTapped(report);
    } on StateError {
      // Report not in list (filtered out)
    }
  },
);
_mapboxMap!.addInteraction(markerTap, interactionID: MapLayerIds.markerTapInteraction);
```

### 7. Caching Strategy

- **Disk cache**: `DefaultCacheManager` (HTTP-aware LRU via `flutter_cache_manager`)
- **In-memory LRU**: Custom `_LruCache<String, Uint8List>` with max 50 entries (~750 KB)
- **Cache key**: `"${url}_${borderColor.toARGB32()}"` — same URL with different border colors are cached separately

## Testing
No dedicated unit tests for marker manager or image service. The `MarkerImageService` is designed for testability (injectable via constructor parameter on `MapMarkerManager`).

## Notes
- The original plan envisioned a Flutter `CrimeMarker` widget rendered to an image bitmap. The actual implementation uses the `image` package in a background isolate — no Flutter widget rendering involved.
- Markers are **rounded squares** (8% corner radius), not circles as originally planned.
- All report images are registered at style-load time (not lazily) to avoid pop-in when zooming.
- The `refreshGeoJsonSource` method allows updating visible markers when crime-type filters change, without re-registering images.
