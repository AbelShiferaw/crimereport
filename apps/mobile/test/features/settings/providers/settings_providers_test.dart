import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crimereport/core/constants/enums.dart';
import 'package:crimereport/features/settings/providers/settings_providers.dart';

void main() {
  group('pushNotificationsEnabledProvider', () {
    test('defaults to true', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(pushNotificationsEnabledProvider), isTrue);
    });

    test('can be toggled', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(pushNotificationsEnabledProvider.notifier).state = false;
      expect(container.read(pushNotificationsEnabledProvider), isFalse);

      container.read(pushNotificationsEnabledProvider.notifier).state = true;
      expect(container.read(pushNotificationsEnabledProvider), isTrue);
    });
  });

  group('notificationRadiusProvider', () {
    test('defaults to 10.0', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(notificationRadiusProvider), 10.0);
    });

    test('can be updated', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(notificationRadiusProvider.notifier).state = 25.0;
      expect(container.read(notificationRadiusProvider), 25.0);
    });

    test('accepts boundary values', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(notificationRadiusProvider.notifier).state = 1.0;
      expect(container.read(notificationRadiusProvider), 1.0);

      container.read(notificationRadiusProvider.notifier).state = 50.0;
      expect(container.read(notificationRadiusProvider), 50.0);
    });
  });

  group('crimeTypeFiltersProvider', () {
    test('defaults to all types enabled', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final filters = container.read(crimeTypeFiltersProvider);
      expect(filters.length, ReportType.values.length);
      for (final type in ReportType.values) {
        expect(filters.contains(type), isTrue);
      }
    });

    test('removing a type filters it out', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final current =
          Set<ReportType>.from(container.read(crimeTypeFiltersProvider));
      current.remove(ReportType.theft);
      container.read(crimeTypeFiltersProvider.notifier).state = current;

      final updated = container.read(crimeTypeFiltersProvider);
      expect(updated.contains(ReportType.theft), isFalse);
      expect(updated.length, ReportType.values.length - 1);
    });

    test('can deselect all', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(crimeTypeFiltersProvider.notifier).state = <ReportType>{};
      expect(container.read(crimeTypeFiltersProvider), isEmpty);
    });

    test('can select all', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(crimeTypeFiltersProvider.notifier).state = <ReportType>{};
      container.read(crimeTypeFiltersProvider.notifier).state =
          Set.from(ReportType.values);

      expect(
        container.read(crimeTypeFiltersProvider).length,
        ReportType.values.length,
      );
    });
  });
}
