import 'package:flutter_test/flutter_test.dart';
import 'package:crimereport/core/utils/geo_utils.dart';

void main() {
  group('GeoUtils', () {
    group('distanceKm', () {
      test('returns 0 for same point', () {
        final d = GeoUtils.distanceKm(37.7749, -122.4194, 37.7749, -122.4194);
        expect(d, 0.0);
      });

      test('calculates known distance between SF and LA', () {
        // SF: 37.7749, -122.4194  LA: 34.0522, -118.2437
        // Real distance ~559 km
        final d = GeoUtils.distanceKm(37.7749, -122.4194, 34.0522, -118.2437);
        expect(d, closeTo(559, 10));
      });

      test('is symmetric (A->B == B->A)', () {
        final ab = GeoUtils.distanceKm(37.7749, -122.4194, 34.0522, -118.2437);
        final ba = GeoUtils.distanceKm(34.0522, -118.2437, 37.7749, -122.4194);
        expect(ab, ba);
      });

      test('handles short distances accurately', () {
        // Two points ~1 block apart in SF
        final d = GeoUtils.distanceKm(37.7749, -122.4194, 37.7759, -122.4184);
        expect(d, closeTo(0.14, 0.05));
      });
    });

    group('distanceMeters', () {
      test('returns 1000x distanceKm', () {
        final km = GeoUtils.distanceKm(37.7749, -122.4194, 34.0522, -118.2437);
        final m = GeoUtils.distanceMeters(37.7749, -122.4194, 34.0522, -118.2437);
        expect(m, km * 1000);
      });
    });

    group('isWithinBounds', () {
      test('returns true for point inside bounds', () {
        expect(
          GeoUtils.isWithinBounds(
            lat: 37.77, lng: -122.42,
            swLat: 37.70, swLng: -122.50,
            neLat: 37.80, neLng: -122.40,
          ),
          isTrue,
        );
      });

      test('returns false for point outside bounds', () {
        expect(
          GeoUtils.isWithinBounds(
            lat: 38.00, lng: -122.42,
            swLat: 37.70, swLng: -122.50,
            neLat: 37.80, neLng: -122.40,
          ),
          isFalse,
        );
      });

      test('returns true for point on boundary edge', () {
        expect(
          GeoUtils.isWithinBounds(
            lat: 37.70, lng: -122.50,
            swLat: 37.70, swLng: -122.50,
            neLat: 37.80, neLng: -122.40,
          ),
          isTrue,
        );
      });

      test('returns false when longitude is out of range', () {
        expect(
          GeoUtils.isWithinBounds(
            lat: 37.75, lng: -122.55,
            swLat: 37.70, swLng: -122.50,
            neLat: 37.80, neLng: -122.40,
          ),
          isFalse,
        );
      });
    });
  });
}
