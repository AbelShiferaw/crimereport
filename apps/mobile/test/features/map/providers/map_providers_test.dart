import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crimereport/core/constants/enums.dart';
import 'package:crimereport/features/map/providers/map_providers.dart';
import 'package:crimereport/features/settings/providers/settings_providers.dart';
import 'package:crimereport/shared/data/mock_data_service.dart';

void main() {
  group('mapReportsProvider', () {
    test('returns all reports when all filters are active', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final reports = container.read(mapReportsProvider);
      final allReports = MockDataService.instance.getReports();
      expect(reports.length, allReports.length);
    });

    test('returns empty when no filters are active', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(crimeTypeFiltersProvider.notifier).state = <ReportType>{};
      final reports = container.read(mapReportsProvider);
      expect(reports, isEmpty);
    });

    test('filters reports by selected crime type', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(crimeTypeFiltersProvider.notifier).state = {
        ReportType.vandalism,
      };

      final reports = container.read(mapReportsProvider);
      for (final report in reports) {
        expect(report.type, ReportType.vandalism);
      }
    });

    test('updates when filters change', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final allCount = container.read(mapReportsProvider).length;

      container.read(crimeTypeFiltersProvider.notifier).state = <ReportType>{};
      expect(container.read(mapReportsProvider).length, 0);

      container.read(crimeTypeFiltersProvider.notifier).state =
          Set.from(ReportType.values);
      expect(container.read(mapReportsProvider).length, allCount);
    });
  });
}
