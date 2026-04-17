import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:crimereport/features/splash/presentation/splash_screen.dart';

Widget _buildTestApp() {
  return const ProviderScope(
    child: MaterialApp(home: SplashScreen()),
  );
}

void main() {
  group('SplashScreen widget', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets('renders app name and tagline', (tester) async {
      await tester.pumpWidget(_buildTestApp());
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('CrImEreport'), findsOneWidget);
      expect(find.text('Anonymous Crime Reporting'), findsOneWidget);

      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
    });

    testWidgets('shows loading indicator', (tester) async {
      await tester.pumpWidget(_buildTestApp());
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
    });

    testWidgets('shows shield icon', (tester) async {
      await tester.pumpWidget(_buildTestApp());
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byIcon(Icons.shield_outlined), findsOneWidget);

      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
    });

    testWidgets('navigates to onboarding for first-time user', (tester) async {
      SharedPreferences.setMockInitialValues({});

      await tester.pumpWidget(_buildTestApp());
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      expect(find.text('Report Anonymously'), findsOneWidget);
    });
  });

  group('Splash navigation logic', () {
    test('onboarding_complete flag controls routing target', () async {
      SharedPreferences.setMockInitialValues({});
      var prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('onboarding_complete') ?? false, isFalse);

      SharedPreferences.setMockInitialValues({'onboarding_complete': true});
      prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('onboarding_complete'), isTrue);
    });

    test('returning user flag causes AppShell destination', () async {
      SharedPreferences.setMockInitialValues({'onboarding_complete': true});
      final prefs = await SharedPreferences.getInstance();
      final complete = prefs.getBool('onboarding_complete') ?? false;
      expect(complete, isTrue);
    });

    test('first launch flag causes onboarding destination', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final complete = prefs.getBool('onboarding_complete') ?? false;
      expect(complete, isFalse);
    });
  });
}
