import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import 'package:crimereport/core/constants/app_constants.dart';
import 'package:crimereport/core/constants/enums.dart';
import 'package:crimereport/features/feed/data/repositories/report_repository.dart';
import 'package:crimereport/features/feed/data/models/report.dart';
import 'package:crimereport/features/settings/providers/settings_providers.dart';

/// User's current location state.
final userLocationProvider = StateProvider<Position?>((ref) => null);

/// Whether location is currently being fetched.
final locationLoadingProvider = StateProvider<bool>((ref) => true);

/// Location permission status.
final locationPermissionProvider =
    StateProvider<LocationPermission?>((ref) => null);

/// Service to handle location operations.
///
/// Abstracts Geolocator calls for testability and reuse.
class LocationService {
  /// Check and request location permissions.
  ///
  /// Returns the current permission status after requesting if needed.
  Future<LocationPermission> checkPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return LocationPermission.denied;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    return permission;
  }

  /// Get current position with timeout.
  ///
  /// Returns null if location cannot be determined.
  Future<Position?> getCurrentPosition() async {
    try {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(AppConstants.locationTimeout);
    } catch (e) {
      return null;
    }
  }

  /// Stream of position updates.
  ///
  /// Updates when user moves [AppConstants.locationDistanceFilter] meters.
  Stream<Position> getPositionStream() {
    return Geolocator.getPositionStream(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: AppConstants.locationDistanceFilter,
      ),
    );
  }

  /// Open device location settings.
  Future<bool> openSettings() async {
    return await Geolocator.openLocationSettings();
  }
}

/// Singleton location service provider.
final locationServiceProvider =
    Provider<LocationService>((ref) => LocationService());

/// Map reports fetched from the REST API and filtered by active crime type
/// filters. Rebuilds when filters or location change so the map can update
/// its GeoJSON source.
final mapReportsProvider = FutureProvider<List<Report>>((ref) async {
  final activeFilters = ref.watch(crimeTypeFiltersProvider);
  final position = ref.watch(userLocationProvider);

  if (position == null) return [];

  final repo = ref.watch(reportRepositoryProvider);
  final allReports = await repo.getNearbyReports(
    lat: position.latitude,
    lng: position.longitude,
    radius: AppConstants.defaultRadiusMeters,
  );

  if (activeFilters.length == ReportType.values.length) return allReports;
  return allReports.where((r) => activeFilters.contains(r.type)).toList();
});
