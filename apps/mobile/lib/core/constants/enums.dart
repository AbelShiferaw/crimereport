import 'package:flutter/material.dart';
import 'package:crimereport/core/theme/colors.dart';

/// Crime report type with display name and associated color.
///
/// The 11 values must stay in sync with the backend `CRIME_TYPES` list
/// (see `backend/api/src/validators/report.ts`). Wire serialization uses
/// [apiName] (snake_case) instead of Dart's enum `name` because
/// `drug_activity` contains an underscore.
enum ReportType {
  theft('theft', 'Theft', AppColors.crimeTheft),
  assault('assault', 'Assault', AppColors.crimeAssault),
  vandalism('vandalism', 'Vandalism', AppColors.crimeVandalism),
  robbery('robbery', 'Robbery', AppColors.crimeRobbery),
  burglary('burglary', 'Burglary', AppColors.crimeBurglary),
  suspicious('suspicious', 'Suspicious Activity', AppColors.crimeSuspicious),
  shooting('shooting', 'Shooting', AppColors.crimeShooting),
  carjacking('carjacking', 'Carjacking', AppColors.crimeCarjacking),
  harassment('harassment', 'Harassment', AppColors.crimeHarassment),
  drugActivity('drug_activity', 'Drug Activity', AppColors.crimeDrug),
  other('other', 'Other', AppColors.crimeOther);

  const ReportType(this.apiName, this.displayName, this.color);

  /// snake_case wire name used by the backend (matches `CRIME_TYPES`).
  final String apiName;

  /// Human-readable name for UI display.
  final String displayName;

  /// Color associated with this crime type for markers and badges.
  final Color color;

  /// Parse a backend wire name (e.g. `drug_activity`) to its enum value.
  /// Throws [ArgumentError] for unknown names.
  static ReportType fromApiName(String apiName) {
    for (final t in ReportType.values) {
      if (t.apiName == apiName) return t;
    }
    throw ArgumentError('Unknown ReportType apiName: $apiName');
  }
}

/// Type of media attached to a report.
enum MediaType {
  video,
  image;

  /// Capitalized name for display.
  String get displayName => name[0].toUpperCase() + name.substring(1);
}

/// Current moderation status of a crime report.
enum ReportStatus {
  pending('Pending Review'),
  uploading('Uploading'),
  processing('Processing'),
  active('Active'),
  failed('Failed'),
  flagged('Flagged'),
  removed('Removed');

  const ReportStatus(this.displayName);

  /// Human-readable status text.
  final String displayName;
}
