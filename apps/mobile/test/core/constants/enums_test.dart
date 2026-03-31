import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crimereport/core/constants/enums.dart';

void main() {
  group('ReportType', () {
    test('has correct number of values', () {
      expect(ReportType.values.length, 7);
    });

    test('each value has a non-empty displayName', () {
      for (final type in ReportType.values) {
        expect(type.displayName, isNotEmpty);
      }
    });

    test('each value has a color', () {
      for (final type in ReportType.values) {
        expect(type.color, isA<Color>());
      }
    });

    test('specific displayName values', () {
      expect(ReportType.theft.displayName, 'Theft');
      expect(ReportType.assault.displayName, 'Assault');
      expect(ReportType.vandalism.displayName, 'Vandalism');
      expect(ReportType.suspicious.displayName, 'Suspicious Activity');
      expect(ReportType.drugActivity.displayName, 'Drug Activity');
      expect(ReportType.disturbance.displayName, 'Disturbance');
      expect(ReportType.other.displayName, 'Other');
    });

    test('all colors are distinct', () {
      final colors = ReportType.values.map((t) => t.color).toSet();
      expect(colors.length, ReportType.values.length);
    });
  });

  group('MediaType', () {
    test('has correct number of values', () {
      expect(MediaType.values.length, 2);
    });

    test('displayName capitalizes first letter', () {
      expect(MediaType.video.displayName, 'Video');
      expect(MediaType.image.displayName, 'Image');
    });
  });

  group('ReportStatus', () {
    test('has correct number of values', () {
      expect(ReportStatus.values.length, 7);
    });

    test('each value has a non-empty displayName', () {
      for (final status in ReportStatus.values) {
        expect(status.displayName, isNotEmpty);
      }
    });

    test('specific displayName values', () {
      expect(ReportStatus.pending.displayName, 'Pending Review');
      expect(ReportStatus.uploading.displayName, 'Uploading');
      expect(ReportStatus.processing.displayName, 'Processing');
      expect(ReportStatus.active.displayName, 'Active');
      expect(ReportStatus.failed.displayName, 'Failed');
      expect(ReportStatus.flagged.displayName, 'Flagged');
      expect(ReportStatus.removed.displayName, 'Removed');
    });
  });
}
