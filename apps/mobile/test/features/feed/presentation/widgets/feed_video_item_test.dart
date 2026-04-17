import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crimereport/core/constants/enums.dart';
import 'package:crimereport/core/theme/theme.dart';
import 'package:crimereport/features/feed/data/models/media.dart';
import 'package:crimereport/features/feed/data/models/report.dart';
import 'package:crimereport/features/feed/presentation/widgets/feed_video_item.dart';
import 'package:crimereport/features/feed/presentation/widgets/feed_action_buttons.dart';
import 'package:crimereport/features/feed/presentation/widgets/feed_info_bar.dart';
import 'package:crimereport/features/feed/presentation/widgets/video_error_placeholder.dart';
import 'package:crimereport/features/feed/presentation/widgets/video_loading_placeholder.dart';
import 'package:crimereport/features/feed/presentation/managers/video_preload_manager.dart';
import 'package:crimereport/features/feed/providers/feed_providers.dart';

final _now = DateTime(2026, 3, 1, 12, 0, 0);

Media _makeMedia({
  String id = 'media_1',
  MediaType type = MediaType.video,
}) {
  return Media(
    id: id,
    reportId: 'report_1',
    type: type,
    url: 'https://example.com/video.mp4',
    thumbnailUrl: 'https://example.com/thumb.jpg',
    durationMs: type == MediaType.video ? 15000 : null,
    width: 1080,
    height: 1920,
    createdAt: _now,
  );
}

Report _makeReport({
  String id = 'report_1',
  List<Media>? media,
  ReportType type = ReportType.theft,
  String description = 'Suspicious activity near the park',
  int upvotes = 42,
  int commentCount = 7,
  double? distanceKm = 1.5,
}) {
  return Report(
    id: id,
    deviceId: 'device_123',
    type: type,
    description: description,
    latitude: 37.7749,
    longitude: -122.4194,
    address: '123 Main St',
    media: media ?? [_makeMedia()],
    upvotes: upvotes,
    commentCount: commentCount,
    createdAt: _now,
    status: ReportStatus.active,
    distanceKm: distanceKm,
  );
}

void main() {
  group('FeedVideoItem', () {
    late VideoPreloadManager preloadManager;

    setUp(() {
      preloadManager = VideoPreloadManager();
    });

    tearDown(() {
      preloadManager.dispose();
    });

    Widget buildTestWidget({
      Report? report,
      bool isActive = false,
      bool ignoreTabState = false,
      List<Override> overrides = const [],
    }) {
      return ProviderScope(
        overrides: overrides,
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 800,
              child: FeedVideoItem(
                report: report ?? _makeReport(),
                isActive: isActive,
                preloadManager: preloadManager,
                ignoreTabState: ignoreTabState,
              ),
            ),
          ),
        ),
      );
    }

    group('initial loading state', () {
      testWidgets('shows loading placeholder while video initializes',
          (tester) async {
        // The video controller initialization will timeout/fail in test
        // environment, so we should see the loading placeholder initially
        await tester.pumpWidget(buildTestWidget());

        // Initially should show loading state since video URL is unreachable
        expect(find.byType(VideoLoadingPlaceholder), findsOneWidget);
      });

      testWidgets('shows action buttons overlay regardless of video state',
          (tester) async {
        await tester.pumpWidget(buildTestWidget());
        await tester.pump();

        expect(find.byType(FeedActionButtons), findsOneWidget);
      });

      testWidgets('shows info bar overlay regardless of video state',
          (tester) async {
        await tester.pumpWidget(buildTestWidget());
        await tester.pump();

        expect(find.byType(FeedInfoBar), findsOneWidget);
      });
    });

    group('report with no media', () {
      testWidgets('shows error placeholder when report has no media',
          (tester) async {
        final report = _makeReport(media: []);

        await tester.pumpWidget(buildTestWidget(report: report));
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.byType(VideoErrorPlaceholder), findsOneWidget);
      });
    });

    group('report with image-only media', () {
      testWidgets('shows error placeholder when primary media is not video',
          (tester) async {
        final imageMedia = _makeMedia(type: MediaType.image);
        final report = _makeReport(media: [imageMedia]);

        await tester.pumpWidget(buildTestWidget(report: report));
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.byType(VideoErrorPlaceholder), findsOneWidget);
      });
    });

    group('report information rendering', () {
      testWidgets('FeedInfoBar shows crime type', (tester) async {
        final report = _makeReport(type: ReportType.assault);

        await tester.pumpWidget(buildTestWidget(report: report));
        await tester.pump();

        // Crime type is displayed uppercase in the info bar
        expect(find.text('ASSAULT'), findsOneWidget);
      });

      testWidgets('FeedInfoBar shows report description', (tester) async {
        const desc = 'Window broken at Main St';
        final report = _makeReport(description: desc);

        await tester.pumpWidget(buildTestWidget(report: report));
        await tester.pump();

        expect(find.text(desc), findsOneWidget);
      });

      testWidgets('FeedActionButtons shows upvote count', (tester) async {
        final report = _makeReport(upvotes: 1500);

        await tester.pumpWidget(buildTestWidget(report: report));
        await tester.pump();

        // 1500 gets formatted as "1.5K"
        expect(find.text('1.5K'), findsOneWidget);
      });

      testWidgets('FeedActionButtons shows comment count', (tester) async {
        final report = _makeReport(commentCount: 25);

        await tester.pumpWidget(buildTestWidget(report: report));
        await tester.pump();

        expect(find.text('25'), findsOneWidget);
      });

      testWidgets('FeedActionButtons shows flag/report button',
          (tester) async {
        await tester.pumpWidget(buildTestWidget());
        await tester.pump();

        expect(find.text('Report'), findsOneWidget);
      });
    });

    group('upvote interaction', () {
      testWidgets('shows non-upvoted state by default', (tester) async {
        await tester.pumpWidget(buildTestWidget());
        await tester.pump();

        expect(
          find.bySemanticsLabel(RegExp('Upvote.*')),
          findsOneWidget,
        );

        final upvoteIcon = tester.widget<Icon>(
          find.byIcon(Icons.arrow_upward_rounded),
        );
        expect(upvoteIcon.color, equals(Colors.white));
      });

      testWidgets('shows upvoted state when report is in upvoted set',
          (tester) async {
        await tester.pumpWidget(buildTestWidget(
          overrides: [
            upvotedReportsProvider
                .overrideWith((ref) => {'report_1'}),
          ],
        ));
        await tester.pump();

        expect(find.byType(FeedActionButtons), findsOneWidget);

        final upvoteIcon = tester.widget<Icon>(
          find.byIcon(Icons.arrow_upward_rounded),
        );
        expect(upvoteIcon.color, equals(AppColors.accent));
      });
    });

    group('different crime types', () {
      for (final crimeType in ReportType.values) {
        testWidgets('renders ${crimeType.name} report correctly',
            (tester) async {
          final report = _makeReport(type: crimeType);

          await tester.pumpWidget(buildTestWidget(report: report));
          await tester.pump();

          expect(
            find.text(crimeType.displayName.toUpperCase()),
            findsOneWidget,
          );
        });
      }
    });

    group('widget lifecycle', () {
      testWidgets('disposes without error', (tester) async {
        await tester.pumpWidget(buildTestWidget());
        await tester.pump();

        // Pump a completely different widget to trigger dispose
        await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      });

      testWidgets('handles being rebuilt with new report', (tester) async {
        final report1 = _makeReport(id: 'r1');
        final report2 = _makeReport(id: 'r2', description: 'Different report');

        await tester.pumpWidget(buildTestWidget(report: report1));
        await tester.pump();

        expect(find.text('Suspicious activity near the park'), findsOneWidget);

        await tester.pumpWidget(buildTestWidget(report: report2));
        await tester.pump();

        expect(find.text('Different report'), findsOneWidget);
      });
    });
  });
}
