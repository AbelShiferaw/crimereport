# Milestone 7: Mapbox Map - Clustering

## Goal

Implement marker clustering so nearby crime markers group together when zoomed out, with stack visualization and count badges.

## Dependencies

Requires **Milestone 6** complete (markers displaying).

## Implementation

### 1. Mapbox Clustering Config

```dart
// Use Mapbox's native clustering via GeoJSON source
await _mapController?.addSource(
  'crimes-source',
  GeojsonSourceProperties(
    data: _buildGeoJson(reports),
    cluster: true,
    clusterMaxZoom: 14,
    clusterRadius: 50,
  ),
);
```

### 2. Cluster Layer

```dart
// Clustered points layer
await _mapController?.addLayer(
  CircleLayerProperties(
    circleColor: '#E53935',
    circleRadius: [
      'step', ['get', 'point_count'],
      20,   // Default size
      10, 25,  // 10+ points = size 25
      50, 30,  // 50+ points = size 30
    ],
  ),
  sourceId: 'crimes-source',
  filter: ['has', 'point_count'],
);

// Cluster count text
await _mapController?.addLayer(
  SymbolLayerProperties(
    textField: ['get', 'point_count_abbreviated'],
    textSize: 12,
    textColor: '#FFFFFF',
  ),
  sourceId: 'crimes-source',
  filter: ['has', 'point_count'],
);
```

### 3. Unclustered Points

```dart
// Individual markers (when zoomed in)
await _mapController?.addLayer(
  SymbolLayerProperties(
    iconImage: 'crime-marker',
    iconSize: 0.4,
  ),
  sourceId: 'crimes-source',
  filter: ['!', ['has', 'point_count']],
);
```

### 4. Cluster Tap → Zoom In

```dart
_mapController?.onFeatureTapped.add((feature) {
  if (feature.properties?['cluster'] == true) {
    // Zoom into cluster
    _mapController?.animateCamera(
      CameraUpdate.newLatLngZoom(
        LatLng(feature.geometry.coordinates[1], feature.geometry.coordinates[0]),
        _mapController!.cameraPosition!.zoom + 2,
      ),
    );
  }
});
```

## Visual Design

| Cluster Size | Circle Radius | Color |

|--------------|---------------|-------|

| 2-9 | 20px | Red |

| 10-49 | 25px | Red |

| 50+ | 30px | Red |

## Deliverable Checklist

- [ ] Markers cluster when zoomed out
- [ ] Cluster shows count badge
- [ ] Tap cluster zooms in
- [ ] Individual markers show when zoomed in
- [ ] Smooth transition between states
- [ ] Performance good with 100+ markers

## Files (2 total)

1. `lib/features/map/presentation/map_screen.dart` - Update with clustering
2. `lib/features/map/data/geojson_builder.dart` - Create GeoJSON converter