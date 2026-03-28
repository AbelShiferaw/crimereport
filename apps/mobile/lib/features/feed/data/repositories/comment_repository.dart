import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:crimereport/shared/data/api/api_client.dart';
import 'package:crimereport/features/feed/data/models/comment.dart';

/// Repository for comment-related REST API calls.
class CommentRepository {
  final ApiClient _client;

  CommentRepository(this._client);

  /// Fetch comments for a report.
  Future<List<Comment>> getComments(
    String reportId, {
    int limit = 20,
    int offset = 0,
  }) async {
    final response = await _client.get<Map<String, dynamic>>(
      '/api/v1/reports/$reportId/comments',
      queryParameters: {'limit': limit, 'offset': offset},
    );

    final data = response.data!['data'] as List<dynamic>;
    return data
        .map((json) => Comment.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// Post a new comment on a report.
  Future<Comment> createComment(String reportId, String content) async {
    final response = await _client.post<Map<String, dynamic>>(
      '/api/v1/reports/$reportId/comments',
      data: {
        'device_id': _client.deviceId,
        'content': content,
      },
    );
    return Comment.fromJson(response.data!);
  }

  /// Flag a comment for moderation. Returns whether the comment is now flagged.
  Future<bool> flagComment(String commentId) async {
    final response = await _client.post<Map<String, dynamic>>(
      '/api/v1/comments/$commentId/flag',
      data: {'device_id': _client.deviceId},
    );
    return response.data!['flagged'] as bool;
  }
}

/// Provider for [CommentRepository].
final commentRepositoryProvider = Provider<CommentRepository>((ref) {
  return CommentRepository(ref.watch(apiClientProvider));
});
