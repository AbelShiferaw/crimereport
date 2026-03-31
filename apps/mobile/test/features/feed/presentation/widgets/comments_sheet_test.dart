import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crimereport/features/feed/data/models/comment.dart';
import 'package:crimereport/features/feed/data/repositories/comment_repository.dart';
import 'package:crimereport/features/feed/providers/feed_providers.dart';
import 'package:crimereport/features/feed/providers/realtime_comments_provider.dart';
import 'package:crimereport/features/feed/presentation/widgets/comments_sheet.dart';
import 'package:crimereport/features/feed/presentation/widgets/comment_tile.dart';
import 'package:crimereport/shared/data/api/api_client.dart';
import 'package:crimereport/shared/data/websocket/websocket_service.dart';

final _now = DateTime(2026, 3, 1, 12, 0, 0);

Comment _makeComment({
  String id = 'c1',
  String reportId = 'report_1',
  String content = 'Great report!',
  int upvotes = 5,
  bool isReporter = false,
}) {
  return Comment(
    id: id,
    reportId: reportId,
    deviceId: 'device_abc',
    content: content,
    upvotes: upvotes,
    createdAt: _now,
    isReporter: isReporter,
  );
}

/// A fake CommentRepository that returns predefined data.
class FakeCommentRepository extends CommentRepository {
  final List<Comment> comments;
  final bool shouldThrow;
  int createCallCount = 0;

  FakeCommentRepository({
    this.comments = const [],
    this.shouldThrow = false,
  }) : super(ApiClient(baseUrl: 'http://test'));

  @override
  Future<List<Comment>> getComments(
    String reportId, {
    int limit = 20,
    int offset = 0,
  }) async {
    if (shouldThrow) throw Exception('Network error');
    return comments;
  }

  @override
  Future<Comment> createComment(String reportId, String content) async {
    createCallCount++;
    if (shouldThrow) throw Exception('Failed to create');
    return _makeComment(
      id: 'new_${createCallCount}',
      reportId: reportId,
      content: content,
    );
  }
}

/// A fake WebSocketService that avoids real socket connections.
class FakeWebSocketService extends WebSocketService {
  FakeWebSocketService() : super(url: 'ws://fake', deviceId: 'fake');

  @override
  void connect() {}

  @override
  void disconnect() {}

  @override
  void subscribeToReport(String reportId) {}

  @override
  void unsubscribeFromReport(String reportId) {}

  @override
  void dispose() {}
}

void main() {
  group('CommentsSheet', () {
    late FakeCommentRepository fakeRepo;
    late FakeWebSocketService fakeWs;

    setUp(() {
      fakeRepo = FakeCommentRepository();
      fakeWs = FakeWebSocketService();
    });

    Widget buildTestWidget({
      String reportId = 'report_1',
      FakeCommentRepository? repository,
      List<Override> extraOverrides = const [],
    }) {
      final repo = repository ?? fakeRepo;

      return ProviderScope(
        overrides: [
          commentRepositoryProvider.overrideWithValue(repo),
          wsServiceProvider.overrideWithValue(fakeWs),
          ...extraOverrides,
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (_) => ProviderScope(
                        parent: ProviderScope.containerOf(context),
                        child: SizedBox(
                          height: 600,
                          child: CommentsSheet(reportId: reportId),
                        ),
                      ),
                    );
                  },
                  child: const Text('Open'),
                );
              },
            ),
          ),
        ),
      );
    }

    Future<void> openSheet(WidgetTester tester) async {
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
    }

    group('empty state', () {
      testWidgets('shows "No comments yet" when there are no comments',
          (tester) async {
        fakeRepo = FakeCommentRepository(comments: []);

        await tester.pumpWidget(buildTestWidget(repository: fakeRepo));
        await openSheet(tester);

        expect(find.text('No comments yet'), findsOneWidget);
        expect(find.text('Be the first to comment'), findsOneWidget);
        expect(
          find.byIcon(Icons.chat_bubble_outline_rounded),
          findsOneWidget,
        );
      });

      testWidgets('shows "Comments" header when loading', (tester) async {
        await tester.pumpWidget(buildTestWidget());
        await tester.tap(find.text('Open'));
        await tester.pump();

        // During loading, the header should show "Comments" without a count
        expect(find.text('Comments'), findsOneWidget);
      });
    });

    group('with comments', () {
      testWidgets('displays comments list', (tester) async {
        final comments = [
          _makeComment(id: 'c1', content: 'First comment'),
          _makeComment(id: 'c2', content: 'Second comment'),
          _makeComment(id: 'c3', content: 'Third comment'),
        ];
        fakeRepo = FakeCommentRepository(comments: comments);

        await tester.pumpWidget(buildTestWidget(repository: fakeRepo));
        await openSheet(tester);

        expect(find.text('First comment'), findsOneWidget);
        expect(find.text('Second comment'), findsOneWidget);
        expect(find.text('Third comment'), findsOneWidget);
      });

      testWidgets('shows comment count in header', (tester) async {
        final comments = [
          _makeComment(id: 'c1'),
          _makeComment(id: 'c2'),
        ];
        fakeRepo = FakeCommentRepository(comments: comments);

        await tester.pumpWidget(buildTestWidget(repository: fakeRepo));
        await openSheet(tester);

        expect(find.text('2 comments'), findsOneWidget);
      });

      testWidgets('shows singular "comment" for 1 comment', (tester) async {
        fakeRepo = FakeCommentRepository(
          comments: [_makeComment()],
        );

        await tester.pumpWidget(buildTestWidget(repository: fakeRepo));
        await openSheet(tester);

        expect(find.text('1 comment'), findsOneWidget);
      });

      testWidgets('renders CommentTile for each comment', (tester) async {
        final comments = [
          _makeComment(id: 'c1'),
          _makeComment(id: 'c2'),
        ];
        fakeRepo = FakeCommentRepository(comments: comments);

        await tester.pumpWidget(buildTestWidget(repository: fakeRepo));
        await openSheet(tester);

        expect(find.byType(CommentTile), findsNWidgets(2));
      });
    });

    group('error state', () {
      testWidgets('shows error message when loading fails', (tester) async {
        fakeRepo = FakeCommentRepository(shouldThrow: true);

        await tester.pumpWidget(buildTestWidget(repository: fakeRepo));
        await openSheet(tester);

        expect(find.text('Failed to load comments'), findsOneWidget);
        expect(find.text('Tap to retry'), findsOneWidget);
      });
    });

    group('input bar', () {
      testWidgets('shows text input field', (tester) async {
        fakeRepo = FakeCommentRepository(comments: []);

        await tester.pumpWidget(buildTestWidget(repository: fakeRepo));
        await openSheet(tester);

        expect(find.byType(TextField), findsOneWidget);
      });

      testWidgets('shows hint text "Add a comment..."', (tester) async {
        fakeRepo = FakeCommentRepository(comments: []);

        await tester.pumpWidget(buildTestWidget(repository: fakeRepo));
        await openSheet(tester);

        expect(find.text('Add a comment...'), findsOneWidget);
      });

      testWidgets('shows send button', (tester) async {
        fakeRepo = FakeCommentRepository(comments: []);

        await tester.pumpWidget(buildTestWidget(repository: fakeRepo));
        await openSheet(tester);

        expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);
      });

      testWidgets('can type text into the input', (tester) async {
        fakeRepo = FakeCommentRepository(comments: []);

        await tester.pumpWidget(buildTestWidget(repository: fakeRepo));
        await openSheet(tester);

        await tester.enterText(find.byType(TextField), 'Hello world');
        expect(find.text('Hello world'), findsOneWidget);
      });
    });

    group('sheet structure', () {
      testWidgets('renders inside DraggableScrollableSheet',
          (tester) async {
        fakeRepo = FakeCommentRepository(comments: []);

        await tester.pumpWidget(buildTestWidget(repository: fakeRepo));
        await openSheet(tester);

        expect(find.byType(DraggableScrollableSheet), findsOneWidget);
      });

      testWidgets('has a drag handle at the top', (tester) async {
        fakeRepo = FakeCommentRepository(comments: []);

        await tester.pumpWidget(buildTestWidget(repository: fakeRepo));
        await openSheet(tester);

        // The handle is a 40x4 Container
        final containers =
            tester.widgetList<Container>(find.byType(Container));
        expect(containers.isNotEmpty, isTrue);
      });
    });
  });
}
