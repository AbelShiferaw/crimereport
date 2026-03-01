# Milestone 1: Project Setup & Structure

## Status
Completed

## Goal
Get the CrImEreport app running with a clean feature-based architecture, all dependencies installed, a dark theme system, and a 4-tab floating bottom navigation showing the Feed, Map, Report, and Settings screens.

## Dependencies
None — this is the foundational milestone.

## What Was Built
A fully structured Flutter project with a feature-based folder layout, comprehensive dark theme system (centralized colors, typography, spacing), Riverpod-based state management, and a floating navigation bar using `google_nav_bar`. The app shell uses `IndexedStack` for tab state preservation and a `Stack`-based layout with a floating nav bar positioned over content.

## Key Files

| File | Description |
|------|-------------|
| `apps/mobile/pubspec.yaml` | Dependencies and project configuration |
| `apps/mobile/lib/main.dart` | App entry point with orientation lock and `.env` loading |
| `apps/mobile/lib/app.dart` | `MaterialApp` wrapper with dark theme and system chrome |
| `apps/mobile/lib/shared/widgets/app_shell.dart` | Navigation shell with `IndexedStack` + floating nav bar |
| `apps/mobile/lib/shared/widgets/floating_nav_bar.dart` | Custom floating nav bar using `google_nav_bar` |
| `apps/mobile/lib/core/theme/app_theme.dart` | Full Material 3 dark theme configuration |
| `apps/mobile/lib/core/theme/colors.dart` | Centralized color palette (brand, crime types, overlays) |
| `apps/mobile/lib/core/theme/typography.dart` | Text styles with video overlay shadows |
| `apps/mobile/lib/core/theme/spacing.dart` | Spacing scale, radii, icon sizes, component sizes |
| `apps/mobile/lib/core/theme/theme.dart` | Barrel export for all theme files |
| `apps/mobile/lib/core/constants/app_constants.dart` | App-wide constants (API, map, video feed, animations) |
| `apps/mobile/lib/core/utils/responsive.dart` | Responsive layout utilities |
| `apps/mobile/lib/features/feed/presentation/feed_screen.dart` | Feed tab screen |
| `apps/mobile/lib/features/map/presentation/map_screen.dart` | Map tab screen |
| `apps/mobile/lib/features/submit/presentation/submit_screen.dart` | Report submission tab |
| `apps/mobile/lib/features/settings/presentation/settings_screen.dart` | Settings tab screen |

## Implementation Details

### Entry Point

`main.dart` initializes Flutter bindings, locks orientation to portrait, loads environment variables from `.env`, and wraps the app in Riverpod's `ProviderScope`:

```dart
// apps/mobile/lib/main.dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  await dotenv.load(fileName: '.env');

  runApp(const ProviderScope(child: CrimeReportApp()));
}
```

### App Root

`app.dart` configures system UI overlays for the dark theme and creates a `MaterialApp` pointing to `AppShell` as the home screen:

```dart
// apps/mobile/lib/app.dart
class CrimeReportApp extends StatelessWidget {
  const CrimeReportApp({super.key});

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: AppColors.background,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );

    return MaterialApp(
      title: 'CrImEreport',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const AppShell(),
    );
  }
}
```

### Navigation Shell

`AppShell` is a `ConsumerStatefulWidget` that uses Riverpod's `appTabIndexProvider` for tab state. It renders screens via `IndexedStack` and overlays the `FloatingNavBar` on top via a `Stack`:

```dart
// apps/mobile/lib/shared/widgets/app_shell.dart
class _AppShellState extends ConsumerState<AppShell> {
  final List<Widget> _screens = const [
    FeedScreen(),
    MapScreen(),
    SubmitScreen(),
    SettingsScreen(),
  ];

  static const List<FloatingNavBarItem> _navItems = [
    FloatingNavBarItem(icon: Icons.home_outlined, activeIcon: Icons.home, label: 'Feed'),
    FloatingNavBarItem(icon: Icons.map_outlined, activeIcon: Icons.map, label: 'Map'),
    FloatingNavBarItem(icon: Icons.add_circle_outline, activeIcon: Icons.add_circle, label: 'Report'),
    FloatingNavBarItem(icon: Icons.settings_outlined, activeIcon: Icons.settings, label: 'Settings'),
  ];

  void _onTabChanged(int index) {
    ref.read(appTabIndexProvider.notifier).state = index;
  }

  @override
  Widget build(BuildContext context) {
    final currentIndex = ref.watch(appTabIndexProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          IndexedStack(index: currentIndex, children: _screens),
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
```

### Floating Navigation Bar

Instead of `BottomNavigationBar`, the app uses a custom floating bar built with `google_nav_bar`. It's positioned absolutely at the bottom with responsive margins and safe area insets. It has a solid dark background with a subtle glass border and shadow:

```dart
// apps/mobile/lib/shared/widgets/floating_nav_bar.dart
class FloatingNavBar extends StatelessWidget {
  // ...
  @override
  Widget build(BuildContext context) {
    final bottomSafeArea = Responsive.bottomSafeArea(context);
    final effectiveBottomMargin = bottomMargin + bottomSafeArea;

    return Positioned(
      left: horizontalMargin,
      right: horizontalMargin,
      bottom: effectiveBottomMargin,
      child: Container(
        height: barHeight,
        decoration: BoxDecoration(
          color: AppColors.navBarBackground,
          borderRadius: borderRadius,
          border: Border.all(color: AppColors.glassBorder, width: 0.5),
          boxShadow: [BoxShadow(color: AppColors.shadowLight, blurRadius: 20, offset: const Offset(0, 8), spreadRadius: -5)],
        ),
        child: ClipRRect(
          borderRadius: borderRadius,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: AppSpacing.sm + AppSpacing.xs, vertical: AppSpacing.sm),
            child: GNav(
              selectedIndex: currentIndex,
              onTabChange: onTap,
              gap: AppSpacing.sm,
              activeColor: AppColors.primary,
              // ...
            ),
          ),
        ),
      ),
    );
  }
}
```

### Theme System

The theme is split across four files exported via a barrel (`theme.dart`):

- **`colors.dart`** — Centralized `AppColors` with brand (`primary: #00897B`), accent red (`#E53935`), 7 crime-type colors, overlay opacity variants (`overlayLight` through `overlayHeavy`), and glass/shadow colors.
- **`typography.dart`** — `AppTypography` with display/headline/title/body/label styles, a `videoOverlayShadow` for text over video.
- **`spacing.dart`** — `AppSpacing` scale from `xxs` (2) to `xxxl` (64), border radii, icon sizes, and nav bar dimensions.
- **`app_theme.dart`** — Full Material 3 `ThemeData` assembling all of the above into card themes, button themes, input decoration, dialog/sheet themes, and more.

### Dependencies

The actual `pubspec.yaml` includes these notable additions over the original plan:

| Category | Package | Notes |
|----------|---------|-------|
| Mapping | `mapbox_maps_flutter: ^2.1.0` | Replaced `mapbox_gl` from original plan |
| Environment | `flutter_dotenv: ^5.1.0` | Added for `.env` config |
| Navigation | `google_nav_bar: ^5.0.6` | For the floating nav bar |
| Image Processing | `flutter_cache_manager: ^3.4.1`, `image: ^4.5.4` | For map marker rendering |
| UI | `cupertino_icons: ^1.0.8` | Standard iOS icons |

SDK constraint: `^3.10.8` (Dart 3.10+).

### Folder Structure (Actual)

```
apps/mobile/lib/
├── main.dart
├── app.dart
├── core/
│   ├── constants/
│   │   ├── app_constants.dart
│   │   └── enums.dart
│   ├── theme/
│   │   ├── app_theme.dart
│   │   ├── colors.dart
│   │   ├── spacing.dart
│   │   ├── typography.dart
│   │   └── theme.dart          (barrel export)
│   └── utils/
│       ├── formatters.dart
│       ├── geo_utils.dart
│       ├── responsive.dart
│       └── utils.dart
├── features/
│   ├── feed/
│   │   ├── data/models/
│   │   ├── presentation/
│   │   └── providers/
│   ├── map/
│   │   ├── presentation/
│   │   ├── providers/
│   │   └── services/
│   ├── submit/
│   │   └── presentation/
│   └── settings/
│       ├── presentation/
│       └── providers/
└── shared/
    ├── data/
    │   ├── mock_data_service.dart
    │   └── sample_data.dart
    └── widgets/
        ├── app_shell.dart
        ├── floating_nav_bar.dart
        ├── loading_placeholder.dart
        ├── permission_placeholder.dart
        ├── responsive_layout.dart
        └── surface_card.dart
```

## Testing
No automated tests were added in this milestone. Verification was done manually:
- App compiles and runs
- 4 tabs visible and tappable
- State preserved between tabs via `IndexedStack`
- Floating nav bar renders above content with safe area padding

## Notes

- **Deviation: Navigation approach** — The original plan used `BottomNavigationBar`. The implementation instead uses a floating `google_nav_bar` overlay positioned via `Positioned` in a `Stack`, giving a more modern TikTok-like appearance where video content extends behind the nav bar.
- **Deviation: Tab state management** — Instead of local `setState` for the tab index, Riverpod's `appTabIndexProvider` is used so other widgets (like `FeedVideoItem`) can react to tab changes (e.g., pause video when leaving the feed tab).
- **Deviation: Theme complexity** — The plan called for a simple `AppTheme` class. The implementation splits the theme into 4 files (colors, typography, spacing, app_theme) with a barrel export, providing a much more comprehensive design system.
- **Deviation: Dependencies** — `mapbox_gl` was replaced with `mapbox_maps_flutter`, `flutter_dotenv` was added for environment config, and `google_nav_bar` was added for the nav bar.
