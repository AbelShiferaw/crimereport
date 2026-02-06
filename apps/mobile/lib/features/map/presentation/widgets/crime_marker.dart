import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/theme.dart';
import '../../../feed/data/models/report.dart';

/// Circular thumbnail marker for displaying crime reports on the map.
///
/// Shows the report's primary media thumbnail with a colored border
/// that matches the crime type. Uses [CachedNetworkImage] for efficient
/// image loading and caching.
class CrimeMarker extends StatelessWidget {
  /// The report to display.
  final Report report;

  /// Callback when the marker is tapped.
  final VoidCallback? onTap;

  /// Size of the marker in logical pixels.
  final double size;

  const CrimeMarker({
    super.key,
    required this.report,
    this.onTap,
    this.size = AppConstants.mapMarkerSize,
  });

  @override
  Widget build(BuildContext context) {
    final thumbnailUrl = report.primaryMedia?.thumbnailUrl ?? 
                         report.primaryMedia?.url;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.background, // Fallback background
          border: Border.all(
            color: report.type.color,
            width: AppConstants.mapMarkerBorderWidth,
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.shadowMedium,
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipOval(
          child: thumbnailUrl != null
              ? CachedNetworkImage(
                  imageUrl: thumbnailUrl,
                  fit: BoxFit.cover,
                  width: size,
                  height: size,
                  placeholder: (context, url) => _buildPlaceholder(),
                  errorWidget: (context, url, error) => _buildFallback(),
                )
              : _buildFallback(),
        ),
      ),
    );
  }

  /// Shimmer placeholder while image loads.
  Widget _buildPlaceholder() {
    return Container(
      color: AppColors.shimmerBase,
      child: Center(
        child: SizedBox(
          width: size * 0.4,
          height: size * 0.4,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: report.type.color,
          ),
        ),
      ),
    );
  }

  /// Fallback when no thumbnail or image fails to load.
  Widget _buildFallback() {
    return Container(
      color: report.type.color.withAlpha(40),
      child: Icon(
        _getCrimeIcon(),
        color: report.type.color,
        size: size * 0.45,
      ),
    );
  }

  /// Get icon based on crime type.
  IconData _getCrimeIcon() {
    switch (report.type.name) {
      case 'theft':
        return Icons.local_police_outlined;
      case 'assault':
        return Icons.warning_amber_rounded;
      case 'vandalism':
        return Icons.format_paint_outlined;
      case 'suspicious':
        return Icons.visibility_outlined;
      case 'drugActivity':
        return Icons.medication_outlined;
      case 'disturbance':
        return Icons.volume_up_outlined;
      default:
        return Icons.report_outlined;
    }
  }
}
