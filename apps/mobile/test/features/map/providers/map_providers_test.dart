import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

import 'package:crimereport/features/map/providers/map_providers.dart';

void main() {
  group('location providers', () {
    test('userLocationProvider defaults to null', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(userLocationProvider), isNull);
    });

    test('locationLoadingProvider defaults to true', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(locationLoadingProvider), isTrue);
    });

    test('locationPermissionProvider defaults to null', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(locationPermissionProvider), isNull);
    });
  });

  group('mapReportsProvider', () {
    test('returns empty list when user location is null', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final reports = await container.read(mapReportsProvider.future);
      expect(reports, isEmpty);
    });
  });
}
