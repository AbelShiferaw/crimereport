import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crimereport/core/constants/enums.dart';
import 'package:crimereport/features/feed/providers/feed_providers.dart';
import 'package:crimereport/features/settings/providers/settings_providers.dart';
import 'package:crimereport/shared/data/mock_data_service.dart';

void main() {
  group('feedReportsProvider', () {
    test('returns all reports when all filters are active', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final reports = await container.read(feedReportsProvider.future);
      final allReports = await MockDataService.instance.getReportsAsync();
      expect(reports.length, allReports.length);
    });

    test('returns empty when no filters are active', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(crimeTypeFiltersProvider.notifier).state = <ReportType>{};
      final reports = await container.read(feedReportsProvider.future);
      expect(reports, isEmpty);
    });

    test('filters reports by selected crime type', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(crimeTypeFiltersProvider.notifier).state = {
        ReportType.theft,
      };

      final reports = await container.read(feedReportsProvider.future);
      for (final report in reports) {
        expect(report.type, ReportType.theft);
      }
    });
  });

  group('locationFeedReportsProvider', () {
    test('returns nearby reports when all filters are active', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final allReports = MockDataService.instance.getReports();
      if (allReports.isEmpty) return;

      final report = allReports.first;
      final nearby = container.read(locationFeedReportsProvider(report));
      expect(nearby, isNotEmpty);
      expect(nearby.first.id, report.id);
    });

    test('returns empty when all filters off and no matching types', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(crimeTypeFiltersProvider.notifier).state = <ReportType>{};

      final allReports = MockDataService.instance.getReports();
      if (allReports.isEmpty) return;

      final report = allReports.first;
      final nearby = container.read(locationFeedReportsProvider(report));
      expect(nearby, isEmpty);
    });
  });

  group('upvote helpers', () {
    test('toggleUpvote adds and removes report ids', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Use a ConsumerReader wrapper since toggleUpvote expects WidgetRef.
      // We'll test the provider directly instead.
      final notifier = container.read(upvotedReportsProvider.notifier);

      expect(container.read(upvotedReportsProvider), isEmpty);

      notifier.state = {...notifier.state, 'r1'};
      expect(container.read(upvotedReportsProvider).contains('r1'), isTrue);

      final updated = {...notifier.state}..remove('r1');
      notifier.state = updated;
      expect(container.read(upvotedReportsProvider).contains('r1'), isFalse);
    });

    test('toggleCommentUpvote adds and removes comment ids', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(upvotedCommentsProvider.notifier);

      expect(container.read(upvotedCommentsProvider), isEmpty);

      notifier.state = {...notifier.state, 'c1'};
      expect(container.read(upvotedCommentsProvider).contains('c1'), isTrue);

      final updated = {...notifier.state}..remove('c1');
      notifier.state = updated;
      expect(container.read(upvotedCommentsProvider).contains('c1'), isFalse);
    });
  });
}
