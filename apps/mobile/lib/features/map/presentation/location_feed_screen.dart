import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/theme.dart';
import '../../feed/data/models/report.dart';
import '../../feed/presentation/widgets/feed_video_item.dart';
import '../../feed/providers/feed_providers.dart';

/// Location-filtered feed screen with glass UI.
///
/// Opens when user taps a marker on the map.
/// Shows reports near the tapped location with the tapped report first.
class LocationFeedScreen extends ConsumerStatefulWidget {
  /// The report that was tapped on the map.
  final Report initialReport;

  const LocationFeedScreen({super.key, required this.initialReport});

  @override
  ConsumerState<LocationFeedScreen> createState() => _LocationFeedScreenState();
}

class _LocationFeedScreenState extends ConsumerState<LocationFeedScreen>
    with WidgetsBindingObserver {
  late PageController _pageController;
  int _currentIndex = 0;
  bool _isScreenActive = true;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final reports = ref.read(
        locationFeedReportsProvider(widget.initialReport),
      );
      ref.read(videoPreloadManagerProvider).preloadAround(reports, 0);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    setState(() {
      _isScreenActive = state == AppLifecycleState.resumed;
    });
  }

  void _onPageChanged(int index) {
    setState(() => _currentIndex = index);

    final reports = ref.read(locationFeedReportsProvider(widget.initialReport));
    ref.read(videoPreloadManagerProvider).preloadAround(reports, index);
  }

  @override
  Widget build(BuildContext context) {
    final reports = ref.watch(
      locationFeedReportsProvider(widget.initialReport),
    );
    final topPadding = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: AppColors.background,
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          // Video feed
          PageView.builder(
            controller: _pageController,
            scrollDirection: Axis.vertical,
            onPageChanged: _onPageChanged,
            itemCount: reports.length,
            itemBuilder: (context, index) {
              return FeedVideoItem(
                key: ValueKey(reports[index].id),
                report: reports[index],
                isActive: index == _currentIndex && _isScreenActive,
                preloadManager: ref.read(videoPreloadManagerProvider),
                ignoreTabState: true, // Bypass tab check for pushed screen
              );
            },
          ),

          // Header overlay
          Positioned(
            top: topPadding + AppSpacing.sm,
            left: AppSpacing.md,
            right: AppSpacing.md,
            child: Row(
              children: [
                // Close button with glass effect
                _GlassCloseButton(onPressed: () => Navigator.of(context).pop()),
                const Spacer(),
                // Location badge with glass effect
                _GlassLocationBadge(reportCount: reports.length),
                const Spacer(),
                // Spacer for symmetry
                const SizedBox(width: 44),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Glass-style close button with blur effect.
class _GlassCloseButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _GlassCloseButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: ClipOval(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.black.withAlpha(64), // 25% opacity
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withAlpha(38), // 15% opacity
                width: 0.5,
              ),
            ),
            child: const Icon(
              Icons.close_rounded,
              color: Colors.white,
              size: 24,
            ),
          ),
        ),
      ),
    );
  }
}

/// Glass-style badge showing number of nearby reports.
class _GlassLocationBadge extends StatelessWidget {
  final int reportCount;

  const _GlassLocationBadge({required this.reportCount});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xs + 2,
          ),
          decoration: BoxDecoration(
            color: Colors.black.withAlpha(64), // 25% opacity
            borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
            border: Border.all(
              color: Colors.white.withAlpha(38), // 15% opacity
              width: 0.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.location_on_rounded,
                color: Colors.white,
                size: 16,
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                '$reportCount nearby',
                style: AppTypography.labelMedium.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
