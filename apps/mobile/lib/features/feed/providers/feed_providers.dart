import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/data/mock_data_service.dart';
import '../data/models/report.dart';
import '../presentation/managers/video_preload_manager.dart';

/// Provider for feed reports - auto disposes when not used.
final feedReportsProvider =
    FutureProvider.autoDispose<List<Report>>((ref) async {
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
