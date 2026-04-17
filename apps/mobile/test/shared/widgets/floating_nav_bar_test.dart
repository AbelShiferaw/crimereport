import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_nav_bar/google_nav_bar.dart';

import 'package:crimereport/shared/widgets/floating_nav_bar.dart';

void main() {
  const testItems = [
    FloatingNavBarItem(
      icon: Icons.home_outlined,
      activeIcon: Icons.home,
      label: 'Feed',
    ),
    FloatingNavBarItem(
      icon: Icons.map_outlined,
      activeIcon: Icons.map,
      label: 'Map',
    ),
    FloatingNavBarItem(
      icon: Icons.add_circle_outline,
      activeIcon: Icons.add_circle,
      label: 'Report',
    ),
    FloatingNavBarItem(
      icon: Icons.settings_outlined,
      activeIcon: Icons.settings,
      label: 'Settings',
    ),
  ];

  Widget buildTestWidget({
    int currentIndex = 0,
    ValueChanged<int>? onTap,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: Stack(
          children: [
            const SizedBox.expand(),
            FloatingNavBar(
              currentIndex: currentIndex,
              onTap: onTap ?? (_) {},
              items: testItems,
            ),
          ],
        ),
      ),
    );
  }

  group('FloatingNavBar', () {
    testWidgets('renders all tab labels', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      expect(find.text('Feed'), findsOneWidget);
      expect(find.text('Map'), findsOneWidget);
      expect(find.text('Report'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
    });

    testWidgets('renders GNav widget with correct number of tabs',
        (tester) async {
      await tester.pumpWidget(buildTestWidget());

      final gNav = tester.widget<GNav>(find.byType(GNav));
      expect(gNav.tabs.length, 4);
    });

    testWidgets('GNav has correct selectedIndex', (tester) async {
      await tester.pumpWidget(buildTestWidget(currentIndex: 2));

      final gNav = tester.widget<GNav>(find.byType(GNav));
      expect(gNav.selectedIndex, 2);
    });

    testWidgets('GNav tab labels match items', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      final gNav = tester.widget<GNav>(find.byType(GNav));
      expect(gNav.tabs[0].text, 'Feed');
      expect(gNav.tabs[1].text, 'Map');
      expect(gNav.tabs[2].text, 'Report');
      expect(gNav.tabs[3].text, 'Settings');
    });

    testWidgets('GNav tab icons match items', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      final gNav = tester.widget<GNav>(find.byType(GNav));
      expect(gNav.tabs[0].icon, Icons.home_outlined);
      expect(gNav.tabs[1].icon, Icons.map_outlined);
      expect(gNav.tabs[2].icon, Icons.add_circle_outline);
      expect(gNav.tabs[3].icon, Icons.settings_outlined);
    });

    testWidgets('calls onTap when tab changes', (tester) async {
      int? tappedIndex;

      await tester.pumpWidget(
        buildTestWidget(onTap: (index) => tappedIndex = index),
      );

      // GNav renders duplicate icons; use .first to select just one
      await tester.tap(find.byIcon(Icons.map_outlined).first);
      await tester.pumpAndSettle();

      expect(tappedIndex, 1);
    });

    testWidgets('calls onTap for last tab', (tester) async {
      int? tappedIndex;

      await tester.pumpWidget(
        buildTestWidget(onTap: (index) => tappedIndex = index),
      );

      await tester.tap(find.byIcon(Icons.settings_outlined).first);
      await tester.pumpAndSettle();

      expect(tappedIndex, 3);
    });

    testWidgets('uses Positioned for floating placement', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      expect(find.byType(Positioned), findsOneWidget);
    });

    testWidgets('renders with different currentIndex values',
        (tester) async {
      for (int i = 0; i < testItems.length; i++) {
        await tester.pumpWidget(buildTestWidget(currentIndex: i));
        await tester.pumpAndSettle();

        final gNav = tester.widget<GNav>(find.byType(GNav));
        expect(gNav.selectedIndex, i);
      }
    });

    testWidgets('has ClipRRect for rounded corners', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      expect(find.byType(ClipRRect), findsOneWidget);
    });

    testWidgets('has a Container with BoxDecoration for styling',
        (tester) async {
      await tester.pumpWidget(buildTestWidget());

      final containers =
          tester.widgetList<Container>(find.byType(Container));
      final decorated = containers.where((c) => c.decoration != null);
      expect(decorated.isNotEmpty, isTrue);
    });
  });

  group('FloatingNavBarItem', () {
    test('stores icon, activeIcon, and label', () {
      const item = FloatingNavBarItem(
        icon: Icons.home_outlined,
        activeIcon: Icons.home,
        label: 'Home',
      );

      expect(item.icon, Icons.home_outlined);
      expect(item.activeIcon, Icons.home);
      expect(item.label, 'Home');
    });
  });
}
