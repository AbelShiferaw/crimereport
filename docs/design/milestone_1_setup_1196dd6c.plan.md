---
name: Milestone 1 Setup
overview: Set up the Flutter project structure with proper folder organization, dependencies, and a working 4-tab navigation shell with placeholder screens.
todos:
  - id: m1-deps
    content: Update pubspec.yaml with all dependencies
    status: pending
  - id: m1-structure
    content: Create folder structure and placeholder files
    status: pending
  - id: m1-theme
    content: Implement dark theme configuration
    status: pending
  - id: m1-shell
    content: Build AppShell with bottom navigation + IndexedStack
    status: pending
  - id: m1-screens
    content: Create 4 placeholder screens
    status: pending
  - id: m1-verify
    content: Run app and verify tabs work correctly
    status: pending
---

# Milestone 1: Project Setup & Structure

## Goal
Get the ReportCrime app running with a clean architecture, all dependencies installed, and 4-tab bottom navigation showing placeholder screens.

## Working File
[lib/main.dart](lib/main.dart) - Currently contains default Flutter counter app, will be replaced entirely.

## Implementation Steps

### 1. Update Dependencies
Add to [pubspec.yaml](pubspec.yaml):

```yaml
dependencies:
  flutter:
    sdk: flutter
  # State Management
  flutter_riverpod: ^2.4.9
  riverpod_annotation: ^2.3.3
  
  # Mapping
  mapbox_gl: ^0.16.0
  
  # Media
  video_player: ^2.8.2
  camera: ^0.10.5+9
  image_picker: ^1.0.7
  
  # Location
  geolocator: ^11.0.0
  permission_handler: ^11.3.0
  
  # Networking (prep for backend)
  dio: ^5.4.0
  socket_io_client: ^2.0.3+1
  
  # Storage
  shared_preferences: ^2.2.2
  flutter_secure_storage: ^9.0.0
  
  # UI Helpers
  cached_network_image: ^3.3.1
  shimmer: ^3.0.0
  
  # Utils
  uuid: ^4.3.3
  intl: ^0.19.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^3.0.0
  riverpod_generator: ^2.3.9
  build_runner: ^2.4.8
```

### 2. Create Folder Structure

```
lib/
├── main.dart                 # App entry point
├── app.dart                  # MaterialApp + ProviderScope
├── core/
│   ├── theme/
│   │   └── app_theme.dart    # Colors, typography, ThemeData
│   └── constants/
│       └── app_constants.dart
├── features/
│   ├── feed/
│   │   └── presentation/
│   │       └── feed_screen.dart      # Placeholder
│   ├── map/
│   │   └── presentation/
│   │       └── map_screen.dart       # Placeholder
│   ├── submit/
│   │   └── presentation/
│   │       └── submit_screen.dart    # Placeholder
│   └── settings/
│       └── presentation/
│           └── settings_screen.dart  # Placeholder
├── shared/
│   └── widgets/
│       └── app_shell.dart    # Bottom nav + IndexedStack
└── router/
    └── app_router.dart       # Navigation config (prep for later)
```

### 3. Implement App Shell with Bottom Navigation

The main navigation structure using `IndexedStack` for preserving state:

```dart
// lib/shared/widgets/app_shell.dart
class AppShell extends ConsumerStatefulWidget {
  @override
  _AppShellState createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _currentIndex = 0;
  
  final _screens = [
    FeedScreen(),
    MapScreen(),
    SubmitScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        type: BottomNavigationBarType.fixed,
        items: [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Feed'),
          BottomNavigationBarItem(icon: Icon(Icons.map), label: 'Map'),
          BottomNavigationBarItem(icon: Icon(Icons.add_circle), label: 'Report'),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}
```

### 4. Create Placeholder Screens

Each screen will be a simple centered text for now:

```dart
// Example: lib/features/feed/presentation/feed_screen.dart
class FeedScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Text('Feed Screen', style: Theme.of(context).textTheme.headlineMedium),
      ),
    );
  }
}
```

### 5. Set Up Theme

Dark theme with accent colors for a crime reporting app:

```dart
// lib/core/theme/app_theme.dart
class AppTheme {
  static ThemeData darkTheme = ThemeData(
    brightness: Brightness.dark,
    primaryColor: Color(0xFFE53935),  // Red accent
    scaffoldBackgroundColor: Color(0xFF121212),
    // ... more styling
  );
}
```

## Deliverable Checklist

- [ ] App compiles and runs on iOS Simulator
- [ ] 4 tabs visible in bottom navigation
- [ ] Can tap between tabs, each shows placeholder text
- [ ] State preserved when switching tabs (IndexedStack working)
- [ ] Clean folder structure created
- [ ] All dependencies resolve correctly

## Files to Create (11 total)

1. `lib/main.dart` - Entry point
2. `lib/app.dart` - MaterialApp wrapper
3. `lib/core/theme/app_theme.dart` - Theme config
4. `lib/core/constants/app_constants.dart` - App constants
5. `lib/features/feed/presentation/feed_screen.dart` - Feed placeholder
6. `lib/features/map/presentation/map_screen.dart` - Map placeholder
7. `lib/features/submit/presentation/submit_screen.dart` - Submit placeholder
8. `lib/features/settings/presentation/settings_screen.dart` - Settings placeholder
9. `lib/shared/widgets/app_shell.dart` - Navigation shell
10. `lib/router/app_router.dart` - Router placeholder
11. `pubspec.yaml` - Updated dependencies

---

Once approved, switch to **agent mode** and I'll implement this milestone.