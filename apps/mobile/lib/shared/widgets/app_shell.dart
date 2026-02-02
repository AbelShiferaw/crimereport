import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/feed/presentation/feed_screen.dart';
import '../../features/feed/providers/feed_providers.dart';
import '../../features/map/presentation/map_screen.dart';
import '../../features/submit/presentation/submit_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import 'floating_nav_bar.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  final List<Widget> _screens = const [
    FeedScreen(),
    MapScreen(),
    SubmitScreen(),
    SettingsScreen(),
  ];

  static const List<FloatingNavBarItem> _navItems = [
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

  void _onTabChanged(int index) {
    // Update the provider so other widgets (like FeedVideoItem) know
    ref.read(appTabIndexProvider.notifier).state = index;
  }

  @override
  Widget build(BuildContext context) {
    final currentIndex = ref.watch(appTabIndexProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // Screen content
          IndexedStack(index: currentIndex, children: _screens),

          // Floating nav bar
          FloatingNavBar(
            currentIndex: currentIndex,
            onTap: _onTabChanged,
            items: _navItems,
          ),
        ],
      ),
    );
  }
}
