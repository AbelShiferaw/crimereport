import 'package:flutter_test/flutter_test.dart';
import 'package:crimereport/core/constants/enums.dart';
import 'package:crimereport/features/feed/data/models/media.dart';

void main() {
  final now = DateTime(2026, 2, 20, 12, 0, 0);

  Media makeMedia({
    String id = 'media_1',
    MediaType type = MediaType.video,
    int? durationMs = 15000,
    int width = 1920,
    int height = 1080,
  }) {
    return Media(
      id: id,
      reportId: 'report_1',
      type: type,
      url: 'https://example.com/video.mp4',
      thumbnailUrl: 'https://example.com/thumb.jpg',
      durationMs: durationMs,
      width: width,
      height: height,
      createdAt: now,
    );
  }

  group('Media', () {
    group('computed properties', () {
      test('isVideo returns true for video type', () {
        final media = makeMedia(type: MediaType.video);
        expect(media.isVideo, isTrue);
      });

      test('isVideo returns false for image type', () {
        final media = makeMedia(type: MediaType.image);
        expect(media.isVideo, isFalse);
      });

      test('durationSeconds converts ms to seconds', () {
        final media = makeMedia(durationMs: 15000);
        expect(media.durationSeconds, 15.0);
      });

      test('durationSeconds returns null when durationMs is null', () {
        final media = makeMedia(durationMs: null);
        expect(media.durationSeconds, isNull);
      });

      test('aspectRatio is width / height', () {
        final media = makeMedia(width: 1920, height: 1080);
        expect(media.aspectRatio, closeTo(1.778, 0.001));
      });

      test('aspectRatio handles square media', () {
        final media = makeMedia(width: 1080, height: 1080);
        expect(media.aspectRatio, 1.0);
      });

      test('aspectRatio handles portrait media', () {
        final media = makeMedia(width: 1080, height: 1920);
        expect(media.aspectRatio, closeTo(0.5625, 0.001));
      });
    });

    group('equality', () {
      test('media with same id are equal', () {
        final a = makeMedia(id: 'm1');
        final b = makeMedia(id: 'm1');
        expect(a, equals(b));
      });

      test('media with different id are not equal', () {
        final a = makeMedia(id: 'm1');
        final b = makeMedia(id: 'm2');
        expect(a, isNot(equals(b)));
      });

      test('hashCode matches for same id', () {
        final a = makeMedia(id: 'm1');
        final b = makeMedia(id: 'm1');
        expect(a.hashCode, equals(b.hashCode));
      });
    });

    group('JSON serialization', () {
      test('toJson produces correct map', () {
        final media = makeMedia();
        final json = media.toJson();
        expect(json['id'], 'media_1');
        expect(json['report_id'], 'report_1');
        expect(json['type'], 'video');
        expect(json['url'], 'https://example.com/video.mp4');
        expect(json['thumbnail_url'], 'https://example.com/thumb.jpg');
        expect(json['duration_ms'], 15000);
        expect(json['width'], 1920);
        expect(json['height'], 1080);
        expect(json['created_at'], isA<String>());
      });

      test('fromJson roundtrip preserves data', () {
        final original = makeMedia();
        final json = original.toJson();
        final restored = Media.fromJson(json);
        expect(restored.id, original.id);
        expect(restored.reportId, original.reportId);
        expect(restored.type, original.type);
        expect(restored.url, original.url);
        expect(restored.thumbnailUrl, original.thumbnailUrl);
        expect(restored.durationMs, original.durationMs);
        expect(restored.width, original.width);
        expect(restored.height, original.height);
      });

      test('fromJson handles null optional fields', () {
        final json = {
          'id': 'm1',
          'report_id': 'r1',
          'type': 'image',
          'url': 'https://example.com/img.jpg',
          'thumbnail_url': null,
          'duration_ms': null,
          'width': 800,
          'height': 600,
          'created_at': '2026-02-20T12:00:00.000',
        };
        final media = Media.fromJson(json);
        expect(media.thumbnailUrl, isNull);
        expect(media.durationMs, isNull);
        expect(media.type, MediaType.image);
      });
    });

    test('toString contains id and type', () {
      final media = makeMedia();
      expect(media.toString(), contains('media_1'));
      expect(media.toString(), contains('video'));
    });
  });
}
