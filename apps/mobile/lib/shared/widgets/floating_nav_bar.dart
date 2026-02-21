import 'package:flutter/material.dart';
import 'package:google_nav_bar/google_nav_bar.dart';

import 'package:crimereport/core/constants/app_constants.dart';
import 'package:crimereport/core/theme/theme.dart';
import 'package:crimereport/core/utils/responsive.dart';

/// A floating bottom navigation bar using google_nav_bar.
/// 
/// Uses solid dark background instead of BackdropFilter blur,
/// ensuring consistent appearance over both Flutter widgets
/// and native platform views (like Mapbox).
class FloatingNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<FloatingNavBarItem> items;

  const FloatingNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    // Responsive margins
    final horizontalMargin = Responsive.value(
      context,
      mobile: AppSpacing.md,
      tablet: AppSpacing.xl,
    );
    final bottomMargin = Responsive.value(
      context,
      mobile: AppSpacing.xs,
      tablet: AppSpacing.sm,
    );

    final bottomSafeArea = Responsive.bottomSafeArea(context);
    final effectiveBottomMargin = bottomMargin + bottomSafeArea;
    final barHeight = Responsive.value(
      context,
      mobile: AppSpacing.floatingNavBarHeight,
      tablet: 72.0,
    );
    final borderRadius = BorderRadius.circular(AppSpacing.radiusXxl);

    return Positioned(
      left: horizontalMargin,
      right: horizontalMargin,
      bottom: effectiveBottomMargin,
      child: Container(
        height: barHeight,
        decoration: BoxDecoration(
          color: AppColors.navBarBackground,
          borderRadius: borderRadius,
          border: Border.all(
            color: AppColors.glassBorder,
            width: 0.5,
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.shadowLight,
              blurRadius: 20,
              offset: const Offset(0, 8),
              spreadRadius: -5,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: borderRadius,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: AppSpacing.sm + AppSpacing.xs,
              vertical: AppSpacing.sm,
            ),
            child: GNav(
              selectedIndex: currentIndex,
              onTabChange: onTap,
              gap: AppSpacing.sm,
              activeColor: AppColors.primary,
              iconSize: AppSpacing.iconMd,
              padding: EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm + AppSpacing.xxs,
              ),
              duration: AppConstants.navBarAnimationDuration,
              tabBackgroundColor: AppColors.primary.withAlpha(30),
              color: AppColors.iconInactive,
              tabs: items.map((item) => GButton(
                icon: item.icon,
                text: item.label,
                iconActiveColor: AppColors.primary,
                textStyle: AppTypography.labelSmall.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              )).toList(),
            ),
          ),
        ),
      ),
    );
  }
}

/// Data class for nav bar items
class FloatingNavBarItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;

  const FloatingNavBarItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });
}
