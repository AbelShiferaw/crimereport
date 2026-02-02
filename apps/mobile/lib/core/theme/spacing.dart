/// Centralized spacing and sizing constants.
/// Use these values for consistent spacing throughout the app.
class AppSpacing {
  AppSpacing._(); // Private constructor

  // ============ Spacing Scale ============
  static const double xxs = 2.0;
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 16.0;
  static const double lg = 24.0;
  static const double xl = 32.0;
  static const double xxl = 48.0;
  static const double xxxl = 64.0;

  // ============ Border Radius ============
  static const double radiusSm = 4.0;
  static const double radiusMdSm = 6.0;
  static const double radiusMd = 8.0;
  static const double radiusLg = 12.0;
  static const double radiusXl = 16.0;
  static const double radiusXxl = 24.0;
  static const double radiusRound = 999.0;

  // ============ Icon Sizes ============
  static const double iconSm = 16.0;
  static const double iconMd = 24.0;
  static const double iconLg = 32.0;
  static const double iconXl = 48.0;

  // ============ Component Sizes ============
  static const double buttonHeight = 48.0;
  static const double buttonHeightSm = 36.0;
  static const double inputHeight = 48.0;
  static const double appBarHeight = 56.0;
  static const double bottomNavHeight = 64.0;
  static const double avatarSm = 32.0;
  static const double avatarMd = 48.0;
  static const double avatarLg = 64.0;

  // ============ Touch Targets ============
  static const double minTouchTarget = 44.0;

  // ============ Content Width ============
  static const double maxContentWidth = 600.0;

  // ============ Floating Nav Bar ============
  static const double floatingNavBarHeight = 64.0;
  static const double floatingNavBarMargin = 16.0;
  
  /// Total space to reserve at bottom for floating nav bar
  /// (height + bottom margin + extra padding)
  static const double floatingNavBarSpace = 100.0;
}
