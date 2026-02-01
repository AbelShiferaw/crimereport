import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/theme.dart';
import '../providers/feed_providers.dart';
import 'widgets/feed_video_item.dart';

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

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
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

    // Ensure status bar is visible with light icons for dark background
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
    );

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

          // Initial preload on first build
          WidgetsBinding.instance.addPostFrameCallback((_) {
            ref
                .read(videoPreloadManagerProvider)
                .preloadAround(reports, currentIndex);
          });

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
                isActive: index == currentIndex,
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.video_library_outlined,
              size: 64,
              color: AppColors.textTertiary,
            ),
            const SizedBox(height: 16),
            Text(
              'No reports yet',
              style: AppTypography.headlineSmall.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Be the first to report a crime in your area',
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textTertiary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
