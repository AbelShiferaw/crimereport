import 'package:flutter_test/flutter_test.dart';
import 'package:crimereport/core/constants/enums.dart';
import 'package:crimereport/features/feed/data/models/report.dart';
import 'package:crimereport/features/feed/data/models/media.dart';

void main() {
  final now = DateTime(2026, 2, 20, 12, 0, 0);

  Media makeMedia({
    String id = 'media_1',
    MediaType type = MediaType.video,
  }) {
    return Media(
      id: id,
      reportId: 'report_1',
      type: type,
      url: 'https://example.com/video.mp4',
      thumbnailUrl: 'https://example.com/thumb.jpg',
      durationMs: type == MediaType.video ? 15000 : null,
      width: 1920,
      height: 1080,
      createdAt: now,
    );
  }

  Report makeReport({
    String id = 'report_1',
    List<Media>? media,
    double? distanceKm,
  }) {
    return Report(
      id: id,
      deviceId: 'device_123',
      type: ReportType.theft,
      description: 'Test description',
      latitude: 37.7749,
      longitude: -122.4194,
      address: '123 Test St',
      media: media ?? [makeMedia()],
      upvotes: 42,
      commentCount: 10,
      createdAt: now,
      status: ReportStatus.verified,
      distanceKm: distanceKm,
    );
  }

  group('Report', () {
    group('computed properties', () {
      test('primaryMedia returns first media item', () {
        final report = makeReport();
        expect(report.primaryMedia, isNotNull);
        expect(report.primaryMedia!.id, 'media_1');
      });

      test('primaryMedia returns null for empty media list', () {
        final report = makeReport(media: []);
        expect(report.primaryMedia, isNull);
      });

      test('hasVideo returns true when media contains video', () {
        final report = makeReport(media: [makeMedia(type: MediaType.video)]);
        expect(report.hasVideo, isTrue);
      });

      test('hasVideo returns false when no video', () {
        final report = makeReport(media: [makeMedia(type: MediaType.image)]);
        expect(report.hasVideo, isFalse);
      });

      test('hasImage returns true when media contains image', () {
        final report = makeReport(media: [makeMedia(type: MediaType.image)]);
        expect(report.hasImage, isTrue);
      });

      test('hasImage returns false when no image', () {
        final report = makeReport(media: [makeMedia(type: MediaType.video)]);
        expect(report.hasImage, isFalse);
      });

      test('distanceText formats distance with 1 decimal', () {
        final report = makeReport(distanceKm: 2.345);
        expect(report.distanceText, '2.3 km');
      });

      test('distanceText returns empty when distanceKm is null', () {
        final report = makeReport(distanceKm: null);
        expect(report.distanceText, '');
      });
    });

    group('timeAgo', () {
      test('returns a non-empty string', () {
        final report = makeReport();
        expect(report.timeAgo, isNotEmpty);
      });
    });

    group('equality', () {
      test('reports with same id are equal', () {
        final a = makeReport(id: 'report_1');
        final b = makeReport(id: 'report_1');
        expect(a, equals(b));
      });

      test('reports with different id are not equal', () {
        final a = makeReport(id: 'report_1');
        final b = makeReport(id: 'report_2');
        expect(a, isNot(equals(b)));
      });

      test('hashCode matches for same id', () {
        final a = makeReport(id: 'report_1');
        final b = makeReport(id: 'report_1');
        expect(a.hashCode, equals(b.hashCode));
      });
    });

    group('copyWith', () {
      test('creates copy with updated fields', () {
        final original = makeReport();
        final copy = original.copyWith(upvotes: 100, description: 'Updated');
        expect(copy.upvotes, 100);
        expect(copy.description, 'Updated');
        expect(copy.id, original.id);
        expect(copy.type, original.type);
      });

      test('preserves all fields when no changes', () {
        final original = makeReport(distanceKm: 1.5);
        final copy = original.copyWith();
        expect(copy.id, original.id);
        expect(copy.distanceKm, original.distanceKm);
        expect(copy.status, original.status);
      });
    });

    group('JSON serialization', () {
      test('toJson produces correct map', () {
        final report = makeReport();
        final json = report.toJson();
        expect(json['id'], 'report_1');
        expect(json['device_id'], 'device_123');
        expect(json['type'], 'theft');
        expect(json['description'], 'Test description');
        expect(json['latitude'], 37.7749);
        expect(json['longitude'], -122.4194);
        expect(json['address'], '123 Test St');
        expect(json['upvotes'], 42);
        expect(json['comment_count'], 10);
        expect(json['status'], 'verified');
        expect(json['media'], isList);
        expect(json['created_at'], isA<String>());
      });

      test('fromJson roundtrip preserves data', () {
        final original = makeReport();
        final json = original.toJson();
        final restored = Report.fromJson(json);
        expect(restored.id, original.id);
        expect(restored.deviceId, original.deviceId);
        expect(restored.type, original.type);
        expect(restored.description, original.description);
        expect(restored.latitude, original.latitude);
        expect(restored.longitude, original.longitude);
        expect(restored.address, original.address);
        expect(restored.upvotes, original.upvotes);
        expect(restored.commentCount, original.commentCount);
        expect(restored.status, original.status);
        expect(restored.media.length, original.media.length);
      });

      test('fromJson handles null optional fields', () {
        final json = {
          'id': 'r1',
          'device_id': 'd1',
          'type': 'theft',
          'description': 'desc',
          'latitude': 37.0,
          'longitude': -122.0,
          'address': null,
          'media': null,
          'upvotes': null,
          'comment_count': null,
          'created_at': '2026-02-20T12:00:00.000',
          'status': 'pending',
        };
        final report = Report.fromJson(json);
        expect(report.address, isNull);
        expect(report.media, isEmpty);
        expect(report.upvotes, 0);
        expect(report.commentCount, 0);
      });
    });

    test('toString contains id and type', () {
      final report = makeReport();
      expect(report.toString(), contains('report_1'));
      expect(report.toString(), contains('theft'));
    });
  });
}
