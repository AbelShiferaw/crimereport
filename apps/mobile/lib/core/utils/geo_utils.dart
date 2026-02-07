import 'dart:math';

/// Geographic utility functions for distance and bounds calculations.
///
/// Provides static methods for common geographic operations like
/// calculating distances between coordinates using the Haversine formula
/// and checking if points are within rectangular bounds.
class GeoUtils {
  GeoUtils._();

  /// Earth's radius in kilometers.
  static const double earthRadiusKm = 6371.0;

  /// Haversine distance between two coordinates in kilometers.
  ///
  /// Uses the Haversine formula to calculate the great-circle distance
  /// between two points on Earth's surface.
  ///
  /// Returns distance in kilometers.
  static double distanceKm(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    final dLat = _toRadians(lat2 - lat1);
    final dLng = _toRadians(lng2 - lng1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat1)) *
            cos(_toRadians(lat2)) *
            sin(dLng / 2) *
            sin(dLng / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadiusKm * c;
  }

  /// Haversine distance between two coordinates in meters.
  ///
  /// Convenience wrapper around [distanceKm] that returns meters.
  static double distanceMeters(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    return distanceKm(lat1, lng1, lat2, lng2) * 1000;
  }

  /// Convert degrees to radians.
  static double _toRadians(double deg) => deg * pi / 180;

  /// Check if a coordinate is within rectangular bounds.
  ///
  /// [lat] and [lng] are the point to check.
  /// [swLat], [swLng] are the southwest corner of the bounds.
  /// [neLat], [neLng] are the northeast corner of the bounds.
  ///
  /// Returns true if the point is within the bounds (inclusive).
  static bool isWithinBounds({
    required double lat,
    required double lng,
    required double swLat,
    required double swLng,
    required double neLat,
    required double neLng,
  }) {
    return lat >= swLat && lat <= neLat && lng >= swLng && lng <= neLng;
  }
}
