import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:crimereport/core/theme/theme.dart';
import 'package:crimereport/features/feed/data/models/report.dart';
import 'package:crimereport/features/feed/presentation/widgets/feed_video_item.dart';
import 'package:crimereport/features/feed/providers/feed_providers.dart';
import 'package:crimereport/shared/widgets/loading_placeholder.dart';
import 'package:crimereport/shared/widgets/api_error_handler.dart';

class LocationFeedScreen extends ConsumerStatefulWidget {
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

  void _onPageChanged(int index, List<Report> reports) {
    setState(() => _currentIndex = index);
    ref.read(videoPreloadManagerProvider).preloadAround(reports, index);
  }

  @override
  Widget build(BuildContext context) {
    final reportsAsync = ref.watch(
      locationFeedReportsProvider(widget.initialReport),
    );
    final topPadding = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: AppColors.background,
      extendBodyBehindAppBar: true,
      body: reportsAsync.when(
        loading: () => const LoadingPlaceholder(message: 'Loading nearby...'),
        error: (error, _) => ApiErrorView(
          error: error,
          onRetry: () => ref.invalidate(
            locationFeedReportsProvider(widget.initialReport),
          ),
        ),
        data: (reports) {
          final safeIndex = reports.isEmpty
              ? 0
              : _currentIndex.clamp(0, reports.length - 1);
          if (safeIndex != _currentIndex && reports.isNotEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              setState(() => _currentIndex = safeIndex);
              if (_pageController.hasClients &&
                  _pageController.page?.round() != safeIndex) {
                _pageController.jumpToPage(safeIndex);
              }
            });
          }

          if (reports.isNotEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              ref
                  .read(videoPreloadManagerProvider)
                  .preloadAround(reports, safeIndex);
            });
          }

          return Stack(
            children: [
              if (reports.isEmpty)
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.filter_alt_off_rounded,
                          size: 48, color: AppColors.textTertiary),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        'No reports match your filters',
                        style: AppTypography.bodyMedium
                            .copyWith(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                )
              else
                PageView.builder(
                  controller: _pageController,
                  scrollDirection: Axis.vertical,
                  onPageChanged: (i) => _onPageChanged(i, reports),
                  itemCount: reports.length,
                  itemBuilder: (context, index) {
                    return FeedVideoItem(
                      key: ValueKey(reports[index].id),
                      report: reports[index],
                      isActive: index == safeIndex && _isScreenActive,
                      preloadManager: ref.read(videoPreloadManagerProvider),
                      ignoreTabState: true,
                    );
                  },
                ),

              Positioned(
                top: topPadding + AppSpacing.sm,
                left: AppSpacing.md,
                right: AppSpacing.md,
                child: Row(
                  children: [
                    _GlassCloseButton(
                        onPressed: () => Navigator.of(context).pop()),
                    const Spacer(),
                    _GlassLocationBadge(reportCount: reports.length),
                    const Spacer(),
                    const SizedBox(width: 44),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

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
              color: AppColors.glassBackground,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.glassBorderLight, width: 0.5),
            ),
            child: const Icon(Icons.close_rounded, color: Colors.white, size: 24),
          ),
        ),
      ),
    );
  }
}

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
            color: AppColors.glassBackground,
            borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
            border: Border.all(color: AppColors.glassBorderLight, width: 0.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.location_on_rounded, color: Colors.white, size: 16),
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
