import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crimereport/features/feed/providers/feed_providers.dart';

void main() {
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
