import 'package:flutter/material.dart';

/// Responsive breakpoints and utilities.
/// Use these to create adaptive layouts across different screen sizes.
class Responsive {
  Responsive._(); // Private constructor

  // ============ Breakpoints ============
  static const double mobileBreakpoint = 600;
  static const double tabletBreakpoint = 900;
  static const double desktopBreakpoint = 1200;

  // ============ Device Type Detection ============
  static bool isMobile(BuildContext context) =>
      MediaQuery.sizeOf(context).width < mobileBreakpoint;

  static bool isTablet(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= mobileBreakpoint &&
      MediaQuery.sizeOf(context).width < desktopBreakpoint;

  static bool isDesktop(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= desktopBreakpoint;

  // ============ Screen Dimensions ============
  static double screenWidth(BuildContext context) =>
      MediaQuery.sizeOf(context).width;

  static double screenHeight(BuildContext context) =>
      MediaQuery.sizeOf(context).height;

  static Size screenSize(BuildContext context) => MediaQuery.sizeOf(context);

  // ============ Safe Area ============
  static EdgeInsets safeAreaPadding(BuildContext context) =>
      MediaQuery.paddingOf(context);

  static double topSafeArea(BuildContext context) =>
      MediaQuery.paddingOf(context).top;

  static double bottomSafeArea(BuildContext context) =>
      MediaQuery.paddingOf(context).bottom;

  // ============ Orientation ============
  static bool isPortrait(BuildContext context) =>
      MediaQuery.orientationOf(context) == Orientation.portrait;

  static bool isLandscape(BuildContext context) =>
      MediaQuery.orientationOf(context) == Orientation.landscape;

  // ============ Text Scale ============
  static double textScale(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(1.0);

  // ============ Responsive Value ============
  /// Returns different values based on screen size
  static T value<T>(
    BuildContext context, {
    required T mobile,
    T? tablet,
    T? desktop,
  }) {
    if (isDesktop(context)) return desktop ?? tablet ?? mobile;
    if (isTablet(context)) return tablet ?? mobile;
    return mobile;
  }

  // ============ Responsive Spacing ============
  /// Returns spacing that scales with screen size
  static double spacing(BuildContext context, double baseSpacing) {
    if (isDesktop(context)) return baseSpacing * 1.5;
    if (isTablet(context)) return baseSpacing * 1.25;
    return baseSpacing;
  }

  // ============ Content Width ============
  /// Maximum content width for readability on large screens
  static const double maxContentWidth = 600;
  static const double maxContentWidthWide = 800;

  /// Returns constrained width for content
  static double contentWidth(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    if (screenWidth > maxContentWidth) return maxContentWidth;
    return screenWidth;
  }
}

/// Device type enum for cleaner conditional logic
enum DeviceType { mobile, tablet, desktop }

extension DeviceTypeExtension on BuildContext {
  DeviceType get deviceType {
    if (Responsive.isDesktop(this)) return DeviceType.desktop;
    if (Responsive.isTablet(this)) return DeviceType.tablet;
    return DeviceType.mobile;
  }
}
