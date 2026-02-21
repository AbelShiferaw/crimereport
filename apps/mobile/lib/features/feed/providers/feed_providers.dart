import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:crimereport/core/constants/app_constants.dart';
import 'package:crimereport/core/constants/enums.dart';
import 'package:crimereport/shared/data/mock_data_service.dart';
import 'package:crimereport/features/settings/providers/settings_providers.dart';
import 'package:crimereport/features/feed/data/models/comment.dart';
import 'package:crimereport/features/feed/data/models/report.dart';
import 'package:crimereport/features/feed/presentation/managers/video_preload_manager.dart';

/// Current app tab index (0=Feed, 1=Map, 2=Submit, 3=Settings).
/// Used to pause videos when navigating away from feed.
final appTabIndexProvider = StateProvider<int>((ref) => 0);

/// Whether the feed tab is currently active.
final isFeedTabActiveProvider = Provider<bool>((ref) {
  return ref.watch(appTabIndexProvider) == 0;
});

/// Provider for feed reports, filtered by active crime type filters.
final feedReportsProvider = FutureProvider.autoDispose<List<Report>>((
  ref,
) async {
  final activeFilters = ref.watch(crimeTypeFiltersProvider);
  final reports = await MockDataService.instance.getReportsAsync();
  if (activeFilters.length == ReportType.values.length) return reports;
  return reports.where((r) => activeFilters.contains(r.type)).toList();
});

/// Current feed index state.
final feedCurrentIndexProvider = StateProvider<int>((ref) => 0);

/// Video preload manager - kept alive for app lifecycle.
final videoPreloadManagerProvider = Provider<VideoPreloadManager>((ref) {
  final manager = VideoPreloadManager();
  ref.onDispose(() => manager.dispose());
  return manager;
});

/// Tracks which reports the user has upvoted (local state).
final upvotedReportsProvider = StateProvider<Set<String>>((ref) => {});

/// Helper to toggle upvote state for a report.
void toggleUpvote(WidgetRef ref, String reportId) {
  final notifier = ref.read(upvotedReportsProvider.notifier);
  final current = notifier.state;
  if (current.contains(reportId)) {
    notifier.state = {...current}..remove(reportId);
  } else {
    notifier.state = {...current, reportId};
  }
}

/// Comments for a given report, fetched with simulated network delay.
final commentsProvider =
    FutureProvider.autoDispose.family<List<Comment>, String>((ref, reportId) {
  return MockDataService.instance.getCommentsAsync(reportId);
});

/// Tracks which comments the user has upvoted (local state).
final upvotedCommentsProvider = StateProvider<Set<String>>((ref) => {});

/// Helper to toggle upvote state for a comment.
void toggleCommentUpvote(WidgetRef ref, String commentId) {
  final notifier = ref.read(upvotedCommentsProvider.notifier);
  final current = notifier.state;
  if (current.contains(commentId)) {
    notifier.state = {...current}..remove(commentId);
  } else {
    notifier.state = {...current, commentId};
  }
}

/// Provider for reports near a specific location, filtered by crime type.
/// Used by LocationFeedScreen when tapping a map marker.
final locationFeedReportsProvider = Provider.family<List<Report>, Report>((
  ref,
  initialReport,
) {
  final activeFilters = ref.watch(crimeTypeFiltersProvider);
  final nearby = MockDataService.instance.getNearbyReports(
    initialReport.latitude,
    initialReport.longitude,
    AppConstants.locationFeedRadiusKm,
  );

  final filtered = nearby.where((r) => activeFilters.contains(r.type)).toList();

  // Ensure the tapped report is first (even if its type is filtered out,
  // keep it since user explicitly tapped this marker)
  final reordered = filtered.where((r) => r.id != initialReport.id).toList();
  if (activeFilters.contains(initialReport.type)) {
    reordered.insert(0, initialReport);
  }
  return reordered;
});
