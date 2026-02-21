import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../shared/data/mock_data_service.dart';
import '../data/models/comment.dart';
import '../data/models/report.dart';
import '../presentation/managers/video_preload_manager.dart';

/// Current app tab index (0=Feed, 1=Map, 2=Submit, 3=Settings).
/// Used to pause videos when navigating away from feed.
final appTabIndexProvider = StateProvider<int>((ref) => 0);

/// Whether the feed tab is currently active.
final isFeedTabActiveProvider = Provider<bool>((ref) {
  return ref.watch(appTabIndexProvider) == 0;
});

/// Provider for feed reports - auto disposes when not used.
final feedReportsProvider = FutureProvider.autoDispose<List<Report>>((
  ref,
) async {
  return MockDataService.instance.getReportsAsync();
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
/// TODO: Persist to local storage in Milestone 13, sync with backend later.
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

/// Provider for reports near a specific location.
/// Used by LocationFeedScreen when tapping a map marker.
final locationFeedReportsProvider = Provider.family<List<Report>, Report>((
  ref,
  initialReport,
) {
  final nearby = MockDataService.instance.getNearbyReports(
    initialReport.latitude,
    initialReport.longitude,
    AppConstants.locationFeedRadiusKm,
  );

  // Ensure the tapped report is first
  final reordered = nearby.where((r) => r.id != initialReport.id).toList();
  reordered.insert(0, initialReport);
  return reordered;
});
