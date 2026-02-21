import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:crimereport/core/constants/enums.dart';
import 'package:crimereport/core/theme/theme.dart';
import 'package:crimereport/features/settings/providers/settings_providers.dart';
import 'package:crimereport/features/feed/providers/feed_providers.dart';
import 'package:crimereport/features/feed/presentation/widgets/feed_video_item.dart';

/// TikTok-style full-screen vertical swipe feed.
///
/// Displays crime reports as full-screen videos that autoplay when visible.
/// Uses Riverpod for state management and [VideoPreloadManager] for
/// efficient video preloading.
class FeedScreen extends ConsumerStatefulWidget {
  const FeedScreen({super.key});

  @override
  ConsumerState<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends ConsumerState<FeedScreen> {
  late PageController _pageController;
  bool _hasInitialPreload = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onPageChanged(int index) {
    // Update current index in provider
    ref.read(feedCurrentIndexProvider.notifier).state = index;

    // Trigger preloading for adjacent videos
    final reportsAsync = ref.read(feedReportsProvider);
    final preloadManager = ref.read(videoPreloadManagerProvider);

    reportsAsync.whenData((reports) {
      preloadManager.preloadAround(reports, index);
    });
  }

  @override
  Widget build(BuildContext context) {
    final reportsAsync = ref.watch(feedReportsProvider);
    final currentIndex = ref.watch(feedCurrentIndexProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      extendBodyBehindAppBar: true,
      body: reportsAsync.when(
        loading: () => _buildLoadingState(),
        error: (error, stack) => _buildErrorState(error),
        data: (reports) {
          if (reports.isEmpty) {
            return _buildEmptyState();
          }

          // Clamp index when the list shrinks (e.g. after a filter change)
          final safeIndex = currentIndex.clamp(0, reports.length - 1);
          if (safeIndex != currentIndex) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              ref.read(feedCurrentIndexProvider.notifier).state = safeIndex;
              if (_pageController.hasClients &&
                  _pageController.page?.round() != safeIndex) {
                _pageController.jumpToPage(safeIndex);
              }
            });
          }

          if (!_hasInitialPreload) {
            _hasInitialPreload = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              ref
                  .read(videoPreloadManagerProvider)
                  .preloadAround(reports, safeIndex);
            });
          }

          return PageView.builder(
            controller: _pageController,
            scrollDirection: Axis.vertical,
            itemCount: reports.length,
            onPageChanged: _onPageChanged,
            itemBuilder: (context, index) {
              final report = reports[index];
              final preloadManager = ref.read(videoPreloadManagerProvider);

              return FeedVideoItem(
                key: ValueKey(report.id),
                report: report,
                isActive: index == safeIndex,
                preloadManager: preloadManager,
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildLoadingState() {
    return const Center(
      child: CircularProgressIndicator(color: AppColors.primary),
    );
  }

  Widget _buildErrorState(Object error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 64,
              color: AppColors.error,
            ),
            const SizedBox(height: 16),
            Text(
              'Failed to load feed',
              style: AppTypography.headlineSmall.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error.toString(),
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textTertiary,
              ),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => ref.invalidate(feedReportsProvider),
              icon: const Icon(Icons.refresh_rounded),
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
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final activeFilters = ref.read(crimeTypeFiltersProvider);
    final allFiltersOff = activeFilters.isEmpty;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              allFiltersOff ? Icons.filter_alt_off_rounded : Icons.video_library_outlined,
              size: 64,
              color: AppColors.textTertiary,
            ),
            const SizedBox(height: 16),
            Text(
              allFiltersOff ? 'All filters are off' : 'No reports yet',
              style: AppTypography.headlineSmall.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              allFiltersOff
                  ? 'Enable crime type filters in Settings to see reports'
                  : 'Be the first to report a crime in your area',
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textTertiary,
              ),
              textAlign: TextAlign.center,
            ),
            if (allFiltersOff) ...[
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () {
                  ref.read(crimeTypeFiltersProvider.notifier).state =
                      Set.from(ReportType.values);
                },
                icon: const Icon(Icons.filter_alt_rounded, size: 18),
                label: const Text('Enable All Filters'),
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
}
