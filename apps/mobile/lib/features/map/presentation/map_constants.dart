/// Layer and source IDs for map markers.
class MapLayerIds {
  static const String source = 'crime-markers-source';
  static const String clusterCircles = 'crime-clusters';
  static const String clusterCount = 'crime-cluster-count';
  static const String unclusteredMarkers = 'crime-unclustered-markers';
  static const String clusterTapInteraction = 'crime-cluster-tap';
  static const String markerTapInteraction = 'crime-marker-tap';

  MapLayerIds._();
}

/// Clustering configuration constants.
class ClusterConfig {
  static const double radius = 50.0;
  static const double maxZoom = 12.0;
  static const int minPoints = 2;

  static const double smallCircleRadius = 18.0;
  static const double mediumCircleRadius = 24.0;
  static const double largeCircleRadius = 30.0;

  ClusterConfig._();
}

/// Zoom-based marker scaling constants.
class ZoomScaling {
  static const double worldView = 0.1;
  static const double country = 0.2;
  static const double city = 0.4;
  static const double neighborhood = 0.6;
  static const double street = 0.8;

  ZoomScaling._();
}

/// Focus pulse animation configuration.
class FocusPulseConfig {
  static const double minRadius = 40.0;
  static const double maxRadius = 70.0;
  static const double maxOpacity = 0.6;
  static const double blur = 0.5;
  static const Duration interval = Duration(milliseconds: 40);
  static const double phaseStep = 0.025;

  /// Minimum zoom level to show focus pulse (past cluster level).
  static const double minZoom = 13.0;

  FocusPulseConfig._();
}
