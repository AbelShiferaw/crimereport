import 'package:flutter_test/flutter_test.dart';
import 'package:crimereport/shared/data/mock_data_service.dart';
import 'package:crimereport/shared/data/sample_data.dart';

void main() {
  late MockDataService service;

  setUp(() {
    service = MockDataService.instance;
  });

  group('MockDataService', () {
    group('getReports', () {
      test('returns all sample reports', () {
        final reports = service.getReports();
        expect(reports.length, SampleData.reports.length);
      });

      test('returns a copy (modifying result does not affect source)', () {
        final reports = service.getReports();
        final originalLength = reports.length;
        reports.removeAt(0);
        expect(service.getReports().length, originalLength);
      });
    });

    group('getReportsByRecent', () {
      test('returns reports sorted by createdAt descending', () {
        final reports = service.getReportsByRecent();
        for (int i = 0; i < reports.length - 1; i++) {
          expect(
            reports[i].createdAt.isAfter(reports[i + 1].createdAt) ||
                reports[i].createdAt.isAtSameMomentAs(reports[i + 1].createdAt),
            isTrue,
            reason: 'Report at index $i should be newer than report at index ${i + 1}',
          );
        }
      });

      test('returns same count as getReports', () {
        expect(service.getReportsByRecent().length, service.getReports().length);
      });
    });

    group('getReportsByPopular', () {
      test('returns reports sorted by upvotes descending', () {
        final reports = service.getReportsByPopular();
        for (int i = 0; i < reports.length - 1; i++) {
          expect(
            reports[i].upvotes >= reports[i + 1].upvotes,
            isTrue,
            reason: 'Report at index $i should have >= upvotes than report at index ${i + 1}',
          );
        }
      });
    });

    group('getNearbyReports', () {
      test('returns reports within radius', () {
        // Center of SF, 10km radius should include all sample data
        final reports = service.getNearbyReports(37.7749, -122.4194, 10.0);
        expect(reports, isNotEmpty);
        for (final r in reports) {
          expect(r.distanceKm, isNotNull);
          expect(r.distanceKm!, lessThanOrEqualTo(10.0));
        }
      });

      test('returns reports sorted by distance ascending', () {
        final reports = service.getNearbyReports(37.7749, -122.4194, 10.0);
        for (int i = 0; i < reports.length - 1; i++) {
          expect(
            reports[i].distanceKm! <= reports[i + 1].distanceKm!,
            isTrue,
            reason: 'Report at index $i should be closer or equal distance',
          );
        }
      });

      test('excludes reports beyond radius', () {
        // Very small radius should filter some out
        final reports = service.getNearbyReports(37.7749, -122.4194, 0.001);
        expect(reports.length, lessThan(SampleData.reports.length));
      });

      test('populates distanceKm on each report', () {
        final reports = service.getNearbyReports(37.7749, -122.4194, 50.0);
        for (final r in reports) {
          expect(r.distanceKm, isNotNull);
          expect(r.distanceKm!, greaterThanOrEqualTo(0));
        }
      });
    });

    group('getReportsAtLocation', () {
      test('finds report at exact coordinates', () {
        final target = SampleData.reports.first;
        final reports = service.getReportsAtLocation(
          target.latitude,
          target.longitude,
        );
        expect(reports, isNotEmpty);
        expect(reports.first.id, target.id);
      });

      test('returns empty for coordinates with no reports', () {
        final reports = service.getReportsAtLocation(0.0, 0.0);
        expect(reports, isEmpty);
      });

      test('respects tolerance parameter', () {
        final target = SampleData.reports.first;
        final reports = service.getReportsAtLocation(
          target.latitude + 0.0001,
          target.longitude + 0.0001,
          tolerance: 0.001,
        );
        expect(reports, isNotEmpty);
      });

      test('excludes reports beyond tolerance', () {
        final target = SampleData.reports.first;
        final reports = service.getReportsAtLocation(
          target.latitude + 0.01,
          target.longitude + 0.01,
          tolerance: 0.001,
        );
        expect(reports.where((r) => r.id == target.id), isEmpty);
      });
    });

    group('getReportById', () {
      test('returns report for valid id', () {
        final report = service.getReportById('report_001');
        expect(report, isNotNull);
        expect(report!.id, 'report_001');
      });

      test('returns null for unknown id', () {
        final report = service.getReportById('nonexistent');
        expect(report, isNull);
      });
    });

    group('getCommentsForReport', () {
      test('returns comments for a known report', () {
        final comments = service.getCommentsForReport('report_001');
        expect(comments, isNotEmpty);
        for (final c in comments) {
          expect(c.reportId, 'report_001');
        }
      });

      test('returns comments sorted by createdAt descending', () {
        final comments = service.getCommentsForReport('report_001');
        for (int i = 0; i < comments.length - 1; i++) {
          expect(
            comments[i].createdAt.isAfter(comments[i + 1].createdAt) ||
                comments[i].createdAt.isAtSameMomentAs(comments[i + 1].createdAt),
            isTrue,
          );
        }
      });

      test('returns empty for report with no comments', () {
        final comments = service.getCommentsForReport('nonexistent');
        expect(comments, isEmpty);
      });
    });

    group('getTopCommentsForReport', () {
      test('returns comments sorted by upvotes descending', () {
        final comments = service.getTopCommentsForReport('report_001');
        for (int i = 0; i < comments.length - 1; i++) {
          expect(
            comments[i].upvotes >= comments[i + 1].upvotes,
            isTrue,
          );
        }
      });
    });

    group('async methods', () {
      test('getReportsAsync returns reports after delay', () async {
        final reports = await service.getReportsAsync(
          delay: const Duration(milliseconds: 10),
        );
        expect(reports, isNotEmpty);
        // Should be sorted by recent (delegates to getReportsByRecent)
        for (int i = 0; i < reports.length - 1; i++) {
          expect(
            reports[i].createdAt.isAfter(reports[i + 1].createdAt) ||
                reports[i].createdAt.isAtSameMomentAs(reports[i + 1].createdAt),
            isTrue,
          );
        }
      });

      test('getNearbyReportsAsync returns nearby reports after delay', () async {
        final reports = await service.getNearbyReportsAsync(
          37.7749, -122.4194, 10.0,
          delay: const Duration(milliseconds: 10),
        );
        expect(reports, isNotEmpty);
        for (final r in reports) {
          expect(r.distanceKm, isNotNull);
        }
      });

      test('getCommentsAsync returns comments after delay', () async {
        final comments = await service.getCommentsAsync(
          'report_001',
          delay: const Duration(milliseconds: 10),
        );
        expect(comments, isNotEmpty);
      });
    });
  });
}
