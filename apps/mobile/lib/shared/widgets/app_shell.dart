import 'package:flutter/material.dart';
import '../../core/theme/theme.dart';
import '../../features/feed/presentation/feed_screen.dart';
import '../../features/map/presentation/map_screen.dart';
import '../../features/submit/presentation/submit_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import 'floating_nav_bar.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _currentIndex = 0;

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // Screen content
          IndexedStack(index: _currentIndex, children: _screens),

          // Floating nav bar
          FloatingNavBar(
            currentIndex: _currentIndex,
            onTap: (index) => setState(() => _currentIndex = index),
            items: _navItems,
          ),
        ],
      ),
    );
  }
}
