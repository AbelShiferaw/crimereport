import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:crimereport/core/constants/app_constants.dart';
import 'package:crimereport/core/constants/enums.dart';
import 'package:crimereport/features/feed/data/repositories/report_repository.dart';
import 'package:crimereport/features/feed/data/repositories/comment_repository.dart';
import 'package:crimereport/features/settings/providers/settings_providers.dart';
import 'package:crimereport/features/feed/data/models/comment.dart';
import 'package:crimereport/features/feed/data/models/report.dart';
import 'package:crimereport/features/feed/presentation/managers/video_preload_manager.dart';
import 'package:crimereport/features/map/providers/map_providers.dart';

/// Current app tab index (0=Feed, 1=Map, 2=Submit, 3=Settings).
/// Used to pause videos when navigating away from feed.
final appTabIndexProvider = StateProvider<int>((ref) => 0);

/// Whether the feed tab is currently active.
final isFeedTabActiveProvider = Provider<bool>((ref) {
  return ref.watch(appTabIndexProvider) == 0;
});

/// Provider for feed reports, filtered by active crime type filters.
///
/// Uses the REST API via [ReportRepository] and the user's current location
/// for nearby report queries. Returns an empty list when location is unknown.
final feedReportsProvider = FutureProvider.autoDispose<List<Report>>((
  ref,
) async {
  final activeFilters = ref.watch(crimeTypeFiltersProvider);
  final position = ref.watch(userLocationProvider);

  if (position == null) return [];

  final repo = ref.watch(reportRepositoryProvider);
  final reports = await repo.getNearbyReports(
    lat: position.latitude,
    lng: position.longitude,
    radius: AppConstants.defaultRadiusMeters,
  );

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

/// Toggle upvote via the REST API, then update local state.
///
/// Safe to call fire-and-forget — errors are caught and logged.
void toggleUpvote(WidgetRef ref, String reportId) {
  final repo = ref.read(reportRepositoryProvider);
  repo.toggleUpvote(reportId).then((upvoted) {
    final notifier = ref.read(upvotedReportsProvider.notifier);
    final current = notifier.state;
    if (upvoted) {
      notifier.state = {...current, reportId};
    } else {
      notifier.state = {...current}..remove(reportId);
    }
    ref.invalidate(feedReportsProvider);
  }).catchError((e) {
    debugPrint('toggleUpvote failed: $e');
  });
}

/// Comments for a given report, fetched from the REST API.
final commentsProvider =
    FutureProvider.autoDispose.family<List<Comment>, String>((ref, reportId) {
  final repo = ref.watch(commentRepositoryProvider);
  return repo.getComments(reportId);
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
///
/// Changed from sync [Provider.family] to [FutureProvider.family] to use
/// the REST API for fetching nearby reports.
final locationFeedReportsProvider =
    FutureProvider.family<List<Report>, Report>((ref, initialReport) async {
  final activeFilters = ref.watch(crimeTypeFiltersProvider);
  final repo = ref.watch(reportRepositoryProvider);

  final nearby = await repo.getNearbyReports(
    lat: initialReport.latitude,
    lng: initialReport.longitude,
    radius: (AppConstants.locationFeedRadiusKm * 1000).round(),
  );

  final filtered =
      nearby.where((r) => activeFilters.contains(r.type)).toList();

  final reordered = filtered.where((r) => r.id != initialReport.id).toList();
  if (activeFilters.contains(initialReport.type)) {
    reordered.insert(0, initialReport);
  }
  return reordered;
});
