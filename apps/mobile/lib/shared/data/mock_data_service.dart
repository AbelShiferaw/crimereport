import 'dart:math';

import '../../features/feed/data/models/comment.dart';
import '../../features/feed/data/models/report.dart';
import 'sample_data.dart';

/// Singleton service providing mock data with query methods.
///
/// This simulates the backend API during development.
/// Will be replaced with real API calls in Phase D (Integration).
class MockDataService {
  MockDataService._internal();

  /// Singleton instance.
  static final MockDataService instance = MockDataService._internal();

  /// Get all reports (unsorted).
  List<Report> getReports() => List.from(SampleData.reports);

  /// Get reports sorted by most recent.
  List<Report> getReportsByRecent() {
    final reports = List<Report>.from(SampleData.reports);
    reports.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return reports;
  }

  /// Get reports sorted by most upvoted.
  List<Report> getReportsByPopular() {
    final reports = List<Report>.from(SampleData.reports);
    reports.sort((a, b) => b.upvotes.compareTo(a.upvotes));
    return reports;
  }

  /// Get reports within a radius of a location.
  ///
  /// Returns reports sorted by distance (nearest first).
  /// Each report's `distanceKm` field is populated.
  List<Report> getNearbyReports(double lat, double lng, double radiusKm) {
    return SampleData.reports
        .map((report) {
          final distance = _haversineDistance(
            lat,
            lng,
            report.latitude,
            report.longitude,
          );
          return report.copyWith(distanceKm: distance);
        })
        .where((r) => r.distanceKm! <= radiusKm)
        .toList()
      ..sort((a, b) => a.distanceKm!.compareTo(b.distanceKm!));
  }

  /// Get reports at a specific location (for map marker tap).
  ///
  /// Uses a small tolerance for coordinate matching.
  List<Report> getReportsAtLocation(
    double lat,
    double lng, {
    double tolerance = 0.001,
  }) {
    return SampleData.reports
        .where(
          (r) =>
              (r.latitude - lat).abs() < tolerance &&
              (r.longitude - lng).abs() < tolerance,
        )
        .toList();
  }

  /// Get a single report by ID.
  Report? getReportById(String id) {
    try {
      return SampleData.reports.firstWhere((r) => r.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Get comments for a specific report.
  ///
  /// Returns comments sorted by most recent first.
  List<Comment> getCommentsForReport(String reportId) {
    return SampleData.comments
        .where((c) => c.reportId == reportId)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  /// Get comments for a report sorted by upvotes.
  List<Comment> getTopCommentsForReport(String reportId) {
    return SampleData.comments
        .where((c) => c.reportId == reportId)
        .toList()
      ..sort((a, b) => b.upvotes.compareTo(a.upvotes));
  }

  /// Calculate distance between two coordinates using Haversine formula.
  ///
  /// Returns distance in kilometers.
  double _haversineDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const earthRadiusKm = 6371.0;

    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);

    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat1)) *
            cos(_toRadians(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);

    final c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return earthRadiusKm * c;
  }

  /// Convert degrees to radians.
  double _toRadians(double degrees) => degrees * pi / 180;

  /// Simulate network delay for realistic testing.
  Future<List<Report>> getReportsAsync({
    Duration delay = const Duration(milliseconds: 500),
  }) async {
    await Future.delayed(delay);
    return getReportsByRecent();
  }

  /// Simulate network delay for nearby reports.
  Future<List<Report>> getNearbyReportsAsync(
    double lat,
    double lng,
    double radiusKm, {
    Duration delay = const Duration(milliseconds: 500),
  }) async {
    await Future.delayed(delay);
    return getNearbyReports(lat, lng, radiusKm);
  }

  /// Simulate network delay for comments.
  Future<List<Comment>> getCommentsAsync(
    String reportId, {
    Duration delay = const Duration(milliseconds: 300),
  }) async {
    await Future.delayed(delay);
    return getCommentsForReport(reportId);
  }
}
