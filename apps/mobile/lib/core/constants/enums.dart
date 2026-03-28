import 'package:flutter/material.dart';
import 'package:crimereport/core/theme/colors.dart';

/// Crime report type with display name and associated color.
enum ReportType {
  theft('Theft', AppColors.crimeTheft),
  assault('Assault', AppColors.crimeAssault),
  vandalism('Vandalism', AppColors.crimeVandalism),
  suspicious('Suspicious Activity', AppColors.crimeSuspicious),
  drugActivity('Drug Activity', AppColors.crimeDrug),
  disturbance('Disturbance', AppColors.crimeDisturbance),
  other('Other', AppColors.crimeOther);

  const ReportType(this.displayName, this.color);

  /// Human-readable name for UI display.
  final String displayName;

  /// Color associated with this crime type for markers and badges.
  final Color color;
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
