import 'dart:ui';
import 'package:flutter/material.dart';
import '../../core/theme/theme.dart';
import '../../core/utils/responsive.dart';

/// A floating bottom navigation bar with iOS-style liquid glass effect.
/// 
/// Features heavy blur, gradient overlay for light refraction, and
/// subtle edge highlights for a premium glass appearance.
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
      mobile: 4.0, // Reduced from 8px to sit lower
      tablet: AppSpacing.sm,
    );

    final bottomSafeArea = Responsive.bottomSafeArea(context);
    final effectiveBottomMargin = bottomMargin + bottomSafeArea;
    final barHeight = Responsive.value(context, mobile: 64.0, tablet: 72.0);
    final borderRadius = BorderRadius.circular(AppSpacing.radiusXxl);

    return Positioned(
      left: horizontalMargin,
      right: horizontalMargin,
      bottom: effectiveBottomMargin,
      child: Container(
        height: barHeight,
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          // Outer glow for "floating" effect
          boxShadow: [
            // Soft ambient shadow
            BoxShadow(
              color: Colors.black.withAlpha(40), // 15%
              blurRadius: 30,
              offset: const Offset(0, 10),
              spreadRadius: -5,
            ),
            // Subtle light glow (simulates light passing through glass)
            BoxShadow(
              color: Colors.white.withAlpha(8), // 3%
              blurRadius: 20,
              offset: const Offset(0, -2),
              spreadRadius: 0,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: borderRadius,
          child: BackdropFilter(
            // Heavy blur for frosted glass
            filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: borderRadius,
                // Gradient for liquid glass light refraction
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white.withAlpha(25), // 10% - top highlight
                    Colors.white.withAlpha(8),  // 3% - middle
                    Colors.white.withAlpha(15), // 6% - bottom reflection
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
                // Subtle border for glass edge
                border: Border.all(
                  color: Colors.white.withAlpha(30), // 12%
                  width: 0.5,
                ),
              ),
              child: Container(
                // Inner container with secondary gradient for depth
                decoration: BoxDecoration(
                  borderRadius: borderRadius,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.white.withAlpha(13), // 5% - top-left highlight
                      Colors.transparent,
                      Colors.black.withAlpha(13), // 5% - bottom-right shadow
                    ],
                    stops: const [0.0, 0.5, 1.0],
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: List.generate(items.length, (index) {
                    final item = items[index];
                    final isSelected = index == currentIndex;

                    return _NavBarItem(
                      icon: isSelected ? item.activeIcon : item.icon,
                      label: item.label,
                      isSelected: isSelected,
                      onTap: () => onTap(index),
                    );
                  }),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavBarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _NavBarItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 64,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 24,
              color: isSelected ? AppColors.primary : Colors.white.withAlpha(180), // Brighter for glass
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                color: isSelected ? AppColors.primary : Colors.white.withAlpha(180),
              ),
            ),
          ],
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
