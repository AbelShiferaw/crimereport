import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crimereport/core/constants/enums.dart';

void main() {
  group('ReportType', () {
    test('has 11 values aligned with backend CRIME_TYPES', () {
      expect(ReportType.values.length, 11);
    });

    test('each value has a non-empty displayName', () {
      for (final type in ReportType.values) {
        expect(type.displayName, isNotEmpty);
      }
    });

    test('each value has a non-empty apiName (snake_case wire format)', () {
      for (final type in ReportType.values) {
        expect(type.apiName, isNotEmpty);
        // apiName must be lowercase snake_case.
        expect(type.apiName, matches(RegExp(r'^[a-z_]+$')));
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
      expect(ReportType.robbery.displayName, 'Robbery');
      expect(ReportType.burglary.displayName, 'Burglary');
      expect(ReportType.suspicious.displayName, 'Suspicious Activity');
      expect(ReportType.shooting.displayName, 'Shooting');
      expect(ReportType.carjacking.displayName, 'Carjacking');
      expect(ReportType.harassment.displayName, 'Harassment');
      expect(ReportType.drugActivity.displayName, 'Drug Activity');
      expect(ReportType.other.displayName, 'Other');
    });

    test('apiName matches backend CRIME_TYPES wire format', () {
      expect(ReportType.theft.apiName, 'theft');
      expect(ReportType.assault.apiName, 'assault');
      expect(ReportType.vandalism.apiName, 'vandalism');
      expect(ReportType.robbery.apiName, 'robbery');
      expect(ReportType.burglary.apiName, 'burglary');
      expect(ReportType.suspicious.apiName, 'suspicious');
      expect(ReportType.shooting.apiName, 'shooting');
      expect(ReportType.carjacking.apiName, 'carjacking');
      expect(ReportType.harassment.apiName, 'harassment');
      expect(ReportType.drugActivity.apiName, 'drug_activity');
      expect(ReportType.other.apiName, 'other');
    });

    test('fromApiName roundtrips every value', () {
      for (final type in ReportType.values) {
        expect(ReportType.fromApiName(type.apiName), type);
      }
    });

    test('fromApiName recognises the snake_case `drug_activity`', () {
      expect(
        ReportType.fromApiName('drug_activity'),
        ReportType.drugActivity,
      );
    });

    test('fromApiName throws for unknown names', () {
      expect(
        () => ReportType.fromApiName('disturbance'),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => ReportType.fromApiName('not_a_crime'),
        throwsA(isA<ArgumentError>()),
      );
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
