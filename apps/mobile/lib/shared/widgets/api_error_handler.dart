import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import 'package:crimereport/core/theme/theme.dart';
import 'package:crimereport/shared/data/api/api_client.dart';

/// Displays a user-friendly error view with an optional retry button.
///
/// Handles [DioException] types, [RateLimitException], and generic errors.
class ApiErrorView extends StatelessWidget {
  final Object error;
  final VoidCallback? onRetry;

  const ApiErrorView({super.key, required this.error, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final (icon, message) = _resolveError(error);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: AppColors.textTertiary),
            const SizedBox(height: AppSpacing.md),
            Text(
              message,
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: AppSpacing.lg),
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static (IconData, String) _resolveError(Object error) {
    if (error is DioException) {
      if (error.error is RateLimitException) {
        return (
          Icons.timer_outlined,
          'Too many requests. Please wait a moment and try again.',
        );
      }

      switch (error.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          return (
            Icons.hourglass_empty_rounded,
            'Connection timed out. Check your network and try again.',
          );
        case DioExceptionType.connectionError:
          return (
            Icons.wifi_off_rounded,
            'Unable to connect. Please check your internet connection.',
          );
        case DioExceptionType.badResponse:
          final statusCode = error.response?.statusCode ?? 0;
          if (statusCode >= 500) {
            return (
              Icons.cloud_off_rounded,
              'Server error. Please try again later.',
            );
          }
          if (statusCode == 404) {
            return (
              Icons.search_off_rounded,
              'The requested resource was not found.',
            );
          }
          return (
            Icons.error_outline_rounded,
            'Request failed (status $statusCode).',
          );
        default:
          return (
            Icons.error_outline_rounded,
            'An unexpected network error occurred.',
          );
      }
    }

    if (error is RateLimitException) {
      return (
        Icons.timer_outlined,
        'Too many requests. Please wait a moment and try again.',
      );
    }

    return (
      Icons.error_outline_rounded,
      'Something went wrong. Please try again.',
    );
  }
}
