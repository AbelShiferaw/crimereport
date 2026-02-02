import 'package:flutter/material.dart';

/// Centralized color palette for the ReportCrime app.
/// Use these colors throughout the app instead of hardcoding values.
class AppColors {
  AppColors._(); // Private constructor to prevent instantiation

  // ============ Brand Colors ============
  static const Color primary = Color(0xFFE53935);
  static const Color primaryLight = Color(0xFFFF6F60);
  static const Color primaryDark = Color(0xFFAB000D);

  // ============ Background Colors ============
  static const Color background = Color(0xFF121212);
  static const Color surface = Color(0xFF1E1E1E);
  static const Color card = Color(0xFF2A2A2A);
  static const Color elevated = Color(0xFF333333);

  // ============ Text Colors ============
  static const Color textPrimary = Colors.white;
  static const Color textSecondary = Color(0xFFB3B3B3);
  static const Color textTertiary = Color(0xFF808080);
  static const Color textDisabled = Color(0xFF4D4D4D);

  // ============ Status Colors ============
  static const Color success = Color(0xFF4CAF50);
  static const Color warning = Color(0xFFFFC107);
  static const Color error = Color(0xFFCF6679);
  static const Color info = Color(0xFF2196F3);

  // ============ Crime Type Colors ============
  static const Color crimeTheft = Color(0xFFFF9800);
  static const Color crimeAssault = Color(0xFFE53935);
  static const Color crimeVandalism = Color(0xFF9C27B0);
  static const Color crimeSuspicious = Color(0xFFFFC107);
  static const Color crimeDrug = Color(0xFF4CAF50);
  static const Color crimeDisturbance = Color(0xFF2196F3);
  static const Color crimeOther = Color(0xFF9E9E9E);

  // ============ UI Element Colors ============
  static const Color divider = Color(0xFF3D3D3D);
  static const Color border = Color(0xFF4D4D4D);
  static const Color overlay = Color(0x80000000); // 50% black
  static const Color shimmerBase = Color(0xFF2A2A2A);
  static const Color shimmerHighlight = Color(0xFF3D3D3D);

  // ============ Overlay & Glass UI Colors ============
  /// Nav bar background - 50% dark grey, glass-like
  static const Color navBarBackground = Color(0x80121212);
  /// 30% black - light overlay for buttons, badges
  static const Color overlayLight = Color(0x4D000000);
  /// 50% black - medium overlay for pause icons, modals
  static const Color overlayMedium = Color(0x80000000);
  /// 60% black - dark overlay for indicators
  static const Color overlayDark = Color(0x99000000);
  /// 80% black - heavy overlay for tooltips, timestamps
  static const Color overlayHeavy = Color(0xCC000000);
  /// 8% white - subtle glass border
  static const Color glassBorder = Color(0x14FFFFFF);
  /// 30% white - progress bar track
  static const Color progressTrack = Color(0x4DFFFFFF);
  /// 70% white - inactive icons on dark backgrounds
  static const Color iconInactive = Color(0xB4FFFFFF);

  // ============ Shadow Colors ============
  /// Light shadow for floating elements - 31% black
  static const Color shadowLight = Color(0x50000000);
  /// Medium shadow for hearts, overlays - 45% black
  static const Color shadowMedium = Color(0x73000000);

  // ============ Gradient Colors ============
  static const List<Color> primaryGradient = [primary, primaryDark];
  static const List<Color> darkGradient = [Color(0xFF1E1E1E), Color(0xFF121212)];
}
