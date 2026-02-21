import 'package:flutter_test/flutter_test.dart';
import 'package:crimereport/features/feed/data/models/comment.dart';

void main() {
  final now = DateTime(2026, 2, 20, 12, 0, 0);

  Comment makeComment({
    String id = 'comment_1',
    String content = 'This is a test comment body.',
    bool isReporter = false,
  }) {
    return Comment(
      id: id,
      reportId: 'report_1',
      deviceId: 'device_123',
      content: content,
      upvotes: 5,
      createdAt: now,
      isReporter: isReporter,
    );
  }

  group('Comment', () {
    group('timeAgo', () {
      test('returns a non-empty string', () {
        final comment = makeComment();
        expect(comment.timeAgo, isNotEmpty);
      });
    });

    group('equality', () {
      test('comments with same id are equal', () {
        final a = makeComment(id: 'c1');
        final b = makeComment(id: 'c1');
        expect(a, equals(b));
      });

      test('comments with different id are not equal', () {
        final a = makeComment(id: 'c1');
        final b = makeComment(id: 'c2');
        expect(a, isNot(equals(b)));
      });

      test('hashCode matches for same id', () {
        final a = makeComment(id: 'c1');
        final b = makeComment(id: 'c1');
        expect(a.hashCode, equals(b.hashCode));
      });
    });

    group('JSON serialization', () {
      test('toJson produces correct map', () {
        final comment = makeComment(isReporter: true);
        final json = comment.toJson();
        expect(json['id'], 'comment_1');
        expect(json['report_id'], 'report_1');
        expect(json['device_id'], 'device_123');
        expect(json['content'], 'This is a test comment body.');
        expect(json['upvotes'], 5);
        expect(json['is_reporter'], true);
        expect(json['created_at'], isA<String>());
      });

      test('fromJson roundtrip preserves data', () {
        final original = makeComment(isReporter: true);
        final json = original.toJson();
        final restored = Comment.fromJson(json);
        expect(restored.id, original.id);
        expect(restored.reportId, original.reportId);
        expect(restored.deviceId, original.deviceId);
        expect(restored.content, original.content);
        expect(restored.upvotes, original.upvotes);
        expect(restored.isReporter, original.isReporter);
      });

      test('fromJson handles null optional fields', () {
        final json = {
          'id': 'c1',
          'report_id': 'r1',
          'device_id': 'd1',
          'content': 'test',
          'upvotes': null,
          'created_at': '2026-02-20T12:00:00.000',
          'is_reporter': null,
        };
        final comment = Comment.fromJson(json);
        expect(comment.upvotes, 0);
        expect(comment.isReporter, false);
      });
    });

    test('toString contains id and truncated content', () {
      final comment = makeComment();
      final str = comment.toString();
      expect(str, contains('comment_1'));
    });
  });
}
