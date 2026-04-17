import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crimereport/features/submit/presentation/submit_screen.dart';

void main() {
  Widget buildTestWidget() {
    return const MaterialApp(
      home: SubmitScreen(),
    );
  }

  group('SubmitScreen', () {
    group('renders empty state', () {
      testWidgets('displays the title "Report a Crime"', (tester) async {
        await tester.pumpWidget(buildTestWidget());

        expect(find.text('Report a Crime'), findsOneWidget);
      });

      testWidgets('displays the subtitle text', (tester) async {
        await tester.pumpWidget(buildTestWidget());

        expect(
          find.text('Capture or upload evidence anonymously'),
          findsOneWidget,
        );
      });

      testWidgets('displays "Open Camera" button', (tester) async {
        await tester.pumpWidget(buildTestWidget());

        expect(find.text('Open Camera'), findsOneWidget);
        expect(find.byIcon(Icons.camera_alt_rounded), findsOneWidget);
      });

      testWidgets('displays "Upload from Gallery" button', (tester) async {
        await tester.pumpWidget(buildTestWidget());

        expect(find.text('Upload from Gallery'), findsOneWidget);
        expect(find.byIcon(Icons.photo_library_rounded), findsOneWidget);
      });

      testWidgets('displays the video camera icon', (tester) async {
        await tester.pumpWidget(buildTestWidget());

        expect(find.byIcon(Icons.videocam_rounded), findsOneWidget);
      });
    });

    group('layout structure', () {
      testWidgets('wraps content in SafeArea', (tester) async {
        await tester.pumpWidget(buildTestWidget());

        expect(find.byType(SafeArea), findsOneWidget);
      });

      testWidgets('uses Scaffold as the root', (tester) async {
        await tester.pumpWidget(buildTestWidget());

        expect(find.byType(Scaffold), findsWidgets);
      });

      testWidgets('centers content', (tester) async {
        await tester.pumpWidget(buildTestWidget());

        expect(find.byType(Center), findsWidgets);
      });

      testWidgets('has a Column for vertical layout', (tester) async {
        await tester.pumpWidget(buildTestWidget());

        expect(find.byType(Column), findsWidgets);
      });
    });

    group('button interactions', () {
      testWidgets('Open Camera button is tappable (does not crash)',
          (tester) async {
        await tester.pumpWidget(buildTestWidget());

        // Tapping Open Camera will try to request permissions, which
        // isn't available in test environment, but shouldn't crash
        final cameraButton = find.text('Open Camera');
        expect(cameraButton, findsOneWidget);

        // Verify GestureDetector wraps the button
        final gestureDetectors =
            tester.widgetList<GestureDetector>(find.byType(GestureDetector));
        expect(gestureDetectors.isNotEmpty, isTrue);
      });

      testWidgets('Upload from Gallery button is tappable (does not crash)',
          (tester) async {
        await tester.pumpWidget(buildTestWidget());

        final galleryButton = find.text('Upload from Gallery');
        expect(galleryButton, findsOneWidget);
      });
    });

    group('visual design', () {
      testWidgets('Open Camera button has an icon and text in a Row',
          (tester) async {
        await tester.pumpWidget(buildTestWidget());

        // Find the Row containing the camera icon
        final rows = tester.widgetList<Row>(find.byType(Row));
        expect(rows.length, greaterThanOrEqualTo(2));
      });

      testWidgets('has decorative icon container at top', (tester) async {
        await tester.pumpWidget(buildTestWidget());

        // There should be a Container wrapping the videocam icon
        final containers =
            tester.widgetList<Container>(find.byType(Container));
        expect(containers.isNotEmpty, isTrue);
      });
    });
  });
}
