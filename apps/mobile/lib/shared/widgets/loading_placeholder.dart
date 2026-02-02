import 'package:flutter/material.dart';

import '../../core/theme/theme.dart';

/// Reusable loading placeholder with spinner and optional message.
///
/// Use for any screen/widget that needs a loading state.
class LoadingPlaceholder extends StatelessWidget {
  final String? message;
  final Color? spinnerColor;

  const LoadingPlaceholder({
    super.key,
    this.message,
    this.spinnerColor,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(
            color: spinnerColor ?? AppColors.primary,
          ),
          if (message != null) ...[
            const SizedBox(height: 16),
            Text(
              message!,
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textTertiary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}
