import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:crimereport/features/onboarding/presentation/onboarding_screen.dart';

void main() {
  group('Onboarding completion state', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('onboarding_complete defaults to false', () async {
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(onboardingCompleteKey), isNull);
    });

    test('setting onboarding_complete persists', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(onboardingCompleteKey, true);
      expect(prefs.getBool(onboardingCompleteKey), isTrue);
    });

    test('onboarding_complete can be reset', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(onboardingCompleteKey, true);
      await prefs.remove(onboardingCompleteKey);
      expect(prefs.getBool(onboardingCompleteKey), isNull);
    });
  });

  group('OnboardingScreen widget', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets('renders first onboarding page', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: OnboardingScreen()),
      );
      await tester.pumpAndSettle();

      expect(find.text('Report Anonymously'), findsOneWidget);
      expect(find.text('Skip'), findsOneWidget);
      expect(find.text('Continue'), findsOneWidget);
    });

    testWidgets('swiping advances to second page', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: OnboardingScreen()),
      );
      await tester.pumpAndSettle();

      await tester.drag(find.byType(PageView), const Offset(-400, 0));
      await tester.pumpAndSettle();

      expect(find.text('Stay Informed'), findsOneWidget);
    });

    testWidgets('last page shows Get Started button', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: OnboardingScreen()),
      );
      await tester.pumpAndSettle();

      // Swipe to page 2
      await tester.drag(find.byType(PageView), const Offset(-400, 0));
      await tester.pumpAndSettle();

      // Swipe to page 3
      await tester.drag(find.byType(PageView), const Offset(-400, 0));
      await tester.pumpAndSettle();

      expect(find.text('Enable Permissions'), findsOneWidget);
      expect(find.text('Get Started'), findsOneWidget);
    });

    testWidgets('Continue button advances page', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: OnboardingScreen()),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(find.text('Stay Informed'), findsOneWidget);
    });

    testWidgets('renders three page dots', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: OnboardingScreen()),
      );
      await tester.pumpAndSettle();

      // Three AnimatedContainer dots
      final dots = find.byType(AnimatedContainer);
      expect(dots, findsNWidgets(3));
    });
  });
}
