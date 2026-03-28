import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crimereport/features/feed/providers/feed_providers.dart';

void main() {
  group('upvote helpers', () {
    test('upvotedReportsProvider adds and removes report ids', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(upvotedReportsProvider.notifier);
      expect(container.read(upvotedReportsProvider), isEmpty);

      notifier.state = {...notifier.state, 'r1'};
      expect(container.read(upvotedReportsProvider).contains('r1'), isTrue);

      final updated = {...notifier.state}..remove('r1');
      notifier.state = updated;
      expect(container.read(upvotedReportsProvider).contains('r1'), isFalse);
    });

    test('upvotedCommentsProvider adds and removes comment ids', () {
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

  group('tab state providers', () {
    test('appTabIndexProvider defaults to 0', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(appTabIndexProvider), 0);
    });

    test('isFeedTabActiveProvider reflects tab index', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(isFeedTabActiveProvider), isTrue);
      container.read(appTabIndexProvider.notifier).state = 1;
      expect(container.read(isFeedTabActiveProvider), isFalse);
      container.read(appTabIndexProvider.notifier).state = 0;
      expect(container.read(isFeedTabActiveProvider), isTrue);
    });
  });
}
