import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:crimereport/shared/data/api/api_client.dart';
import 'package:crimereport/features/feed/data/models/report.dart';

/// Repository for report-related REST API calls.
class ReportRepository {
  final ApiClient _client;

  ReportRepository(this._client);

  /// Fetch reports near the given coordinates.
  Future<List<Report>> getNearbyReports({
    required double lat,
    required double lng,
    required int radius,
    int limit = 20,
    int offset = 0,
  }) async {
    final response = await _client.get<Map<String, dynamic>>(
      '/api/v1/reports',
      queryParameters: {
        'lat': lat,
        'lng': lng,
        'radius': radius,
        'limit': limit,
        'offset': offset,
      },
    );

    final data = response.data!['data'] as List<dynamic>;
    return data
        .map((json) => Report.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// Fetch a single report by ID (includes media array).
  Future<Report> getReport(String id) async {
    final response = await _client.get<Map<String, dynamic>>(
      '/api/v1/reports/$id',
    );
    return Report.fromJson(response.data!);
  }

  /// Create a new report. The device_id is sent via X-Device-ID header.
  Future<Report> createReport({
    required String type,
    required String description,
    required double lat,
    required double lng,
    String? address,
  }) async {
    final body = <String, dynamic>{
      'device_id': _client.deviceId,
      'type': type,
      'description': description,
      'lat': lat,
      'lng': lng,
    };
    if (address != null) body['address'] = address;

    final response = await _client.post<Map<String, dynamic>>(
      '/api/v1/reports',
      data: body,
    );
    return Report.fromJson(response.data!);
  }

  /// Toggle upvote on a report. Returns whether the report is now upvoted.
  Future<bool> toggleUpvote(String reportId) async {
    final response = await _client.post<Map<String, dynamic>>(
      '/api/v1/reports/$reportId/upvote',
      data: {'device_id': _client.deviceId},
    );
    return response.data!['upvoted'] as bool;
  }
}

/// Provider for [ReportRepository].
final reportRepositoryProvider = Provider<ReportRepository>((ref) {
  return ReportRepository(ref.watch(apiClientProvider));
});
