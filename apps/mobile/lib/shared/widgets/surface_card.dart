import 'package:flutter/material.dart';

import 'package:crimereport/core/theme/theme.dart';

/// Standard card container with surface background and rounded corners.
///
/// Used throughout the app for settings tiles, form sections,
/// and other card-like containers.
class SurfaceCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Border? border;

  const SurfaceCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      margin: margin,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: border,
      ),
      child: child,
    );
  }
}
