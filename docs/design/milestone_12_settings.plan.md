# Milestone 12: Settings Screen

## Status
Completed

## Goal
Build the settings screen with notification preferences (push toggle, radius slider), crime type filter toggles, privacy info, about/legal sections, and anonymous device ID display.

## Dependencies
Requires **Milestone 1** complete (project structure with `flutter_riverpod`, `shared_preferences`, `uuid` packages).

## What Was Built
- `SettingsScreen` — a `ConsumerWidget` with sections for Notifications, Crime Type Filters, Privacy, and About
- Push notification toggle with conditional radius slider (1–50 km range with numeric display)
- Per-crime-type filter toggles with Select All / Deselect All functionality
- Privacy section showing anonymous mode status
- About section with app version, privacy policy, terms of service (navigating to `LegalTextScreen`), and help/support
- Anonymous ID card using `FutureProvider` backed by `SharedPreferences` with UUID generation on first launch
- `LegalTextScreen` — full-page scrollable text screen for privacy policy and terms of service content
- `settings_providers.dart` — Riverpod state providers for push notifications, notification radius, crime type filters, and anonymous ID
- Responsive layout using `Responsive` utility and `SurfaceCard` widget

## Key Files
| File | Description |
|------|-------------|
| `apps/mobile/lib/features/settings/presentation/settings_screen.dart` | Main settings screen with all sections, `_SectionHeader` and `_SettingsTile` widgets |
| `apps/mobile/lib/features/settings/providers/settings_providers.dart` | Riverpod providers: `pushNotificationsEnabledProvider`, `notificationRadiusProvider`, `crimeTypeFiltersProvider`, `anonymousIdProvider` |
| `apps/mobile/lib/features/settings/presentation/legal_text_screen.dart` | Legal text viewer + `LegalContent` class with static privacy policy and terms of service strings |
| `apps/mobile/lib/shared/widgets/surface_card.dart` | Reusable card widget used for settings tiles |
| `apps/mobile/lib/core/utils/responsive.dart` | `Responsive.value()` and `Responsive.maxContentWidth` used for adaptive layout |

## Implementation Details

### 1. Settings Providers

All settings state is managed via Riverpod `StateProvider`s. The anonymous ID uses a `FutureProvider` that generates a UUID v4 on first launch and persists it in `SharedPreferences`:

```dart
final pushNotificationsEnabledProvider = StateProvider<bool>((ref) => true);

final notificationRadiusProvider = StateProvider<double>((ref) => 10.0);

final crimeTypeFiltersProvider = StateProvider<Set<ReportType>>(
  (ref) => Set.from(ReportType.values),
);

const _anonymousIdKey = 'anonymous_device_id';

final anonymousIdProvider = FutureProvider<String>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  final existing = prefs.getString(_anonymousIdKey);
  if (existing != null) return existing;

  final newId = const Uuid().v4();
  await prefs.setString(_anonymousIdKey, newId);
  return newId;
});
```

### 2. Settings Screen — ConsumerWidget Structure

The screen watches three providers and delegates to section builder methods. Uses `ConstrainedBox` with `Responsive.maxContentWidth` for tablet support:

```dart
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pushEnabled = ref.watch(pushNotificationsEnabledProvider);
    final radius = ref.watch(notificationRadiusProvider);
    final activeFilters = ref.watch(crimeTypeFiltersProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: Responsive.maxContentWidth,
            ),
            child: ListView(
              padding: EdgeInsets.all(
                Responsive.value(context, mobile: AppSpacing.md, tablet: AppSpacing.lg),
              ),
              children: [
                _buildNotificationsSection(context, ref, pushEnabled, radius),
                const SizedBox(height: AppSpacing.lg),
                _buildCrimeTypeSection(context, ref, activeFilters),
                const SizedBox(height: AppSpacing.lg),
                _buildPrivacySection(context),
                const SizedBox(height: AppSpacing.lg),
                _buildAboutSection(context),
                const SizedBox(height: AppSpacing.xl),
                _buildAnonymousIdCard(ref),
                SizedBox(height: AppSpacing.floatingNavBarSpace),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

### 3. Notification Section with Conditional Radius Slider

The push toggle shows/hides the radius slider. The slider uses `SurfaceCard` with a themed `SliderTheme`, 1–49 divisions for 1–50 km range, and a styled km badge:

```dart
Widget _buildNotificationsSection(
  BuildContext context, WidgetRef ref, bool pushEnabled, double radius,
) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _SectionHeader(title: 'Notifications'),
      _SettingsTile(
        icon: Icons.notifications_outlined,
        title: 'Push Notifications',
        subtitle: pushEnabled ? 'Enabled' : 'Disabled',
        trailing: Switch(
          value: pushEnabled,
          onChanged: (v) =>
              ref.read(pushNotificationsEnabledProvider.notifier).state = v,
          activeTrackColor: AppColors.primary.withValues(alpha: 0.5),
          activeThumbColor: AppColors.primary,
        ),
      ),
      if (pushEnabled) ...[
        const SizedBox(height: AppSpacing.xs),
        _buildRadiusSlider(context, ref, radius),
      ],
    ],
  );
}
```

The radius slider card:

```dart
Widget _buildRadiusSlider(BuildContext context, WidgetRef ref, double radius) {
  return SurfaceCard(
    padding: const EdgeInsets.all(AppSpacing.md),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          // Radar icon in box
          // "Notification Radius" title + subtitle
          // "${radius.round()} km" badge
        ]),
        const SizedBox(height: AppSpacing.sm),
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: AppColors.primary,
            inactiveTrackColor: AppColors.card,
            thumbColor: AppColors.primary,
            overlayColor: AppColors.primary.withAlpha(30),
            trackHeight: 4,
          ),
          child: Slider(
            value: radius, min: 1, max: 50, divisions: 49,
            onChanged: (v) =>
                ref.read(notificationRadiusProvider.notifier).state = v,
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('1 km', style: AppTypography.caption),
            Text('50 km', style: AppTypography.caption),
          ],
        ),
      ],
    ),
  );
}
```

### 4. Crime Type Filter Toggles

Each `ReportType` gets a `SurfaceCard` with a `ListTile` containing a colored dot and a `Switch`. A header row offers "Select All" / "Deselect All":

```dart
Widget _buildCrimeTypeSection(
  BuildContext context, WidgetRef ref, Set<ReportType> activeFilters,
) {
  final allSelected = activeFilters.length == ReportType.values.length;

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _SectionHeader(title: 'Crime Type Filters'),
          GestureDetector(
            onTap: () {
              final notifier = ref.read(crimeTypeFiltersProvider.notifier);
              notifier.state = allSelected
                  ? <ReportType>{}
                  : Set.from(ReportType.values);
            },
            child: Text(
              allSelected ? 'Deselect All' : 'Select All',
              style: AppTypography.caption.copyWith(
                color: AppColors.primary, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
      ...ReportType.values.map(
        (type) => _buildCrimeTypeToggle(ref, type, activeFilters),
      ),
    ],
  );
}
```

Individual toggle:

```dart
Widget _buildCrimeTypeToggle(
  WidgetRef ref, ReportType type, Set<ReportType> activeFilters,
) {
  final isActive = activeFilters.contains(type);
  return SurfaceCard(
    margin: const EdgeInsets.only(bottom: AppSpacing.sm),
    child: ListTile(
      leading: Container(/* 40x40 box with colored dot */),
      title: Text(type.displayName, style: AppTypography.titleSmall),
      trailing: Switch(
        value: isActive,
        onChanged: (v) {
          final notifier = ref.read(crimeTypeFiltersProvider.notifier);
          final current = Set<ReportType>.from(notifier.state);
          v ? current.add(type) : current.remove(type);
          notifier.state = current;
        },
        activeTrackColor: AppColors.primary.withValues(alpha: 0.5),
        activeThumbColor: AppColors.primary,
      ),
    ),
  );
}
```

### 5. About Section with Legal Text Navigation

Privacy Policy and Terms of Service navigate to `LegalTextScreen` via `MaterialPageRoute`. The legal content is stored as static `const String` fields in `LegalContent`:

```dart
_SettingsTile(
  icon: Icons.description_outlined,
  title: 'Privacy Policy',
  onTap: () => Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => const LegalTextScreen(
      title: 'Privacy Policy',
      body: LegalContent.privacyPolicy,
    ),
  )),
),
```

`LegalTextScreen` is a simple `Scaffold` with `SingleChildScrollView` and responsive padding:

```dart
class LegalTextScreen extends StatelessWidget {
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(title), backgroundColor: AppColors.surface),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: Responsive.maxContentWidth),
            child: SingleChildScrollView(
              padding: EdgeInsets.all(
                Responsive.value(context, mobile: AppSpacing.md, tablet: AppSpacing.lg),
              ),
              child: Text(body, style: AppTypography.bodyMedium),
            ),
          ),
        ),
      ),
    );
  }
}
```

### 6. Anonymous ID Card

Watches `anonymousIdProvider` (a `FutureProvider`) and renders loading/error/data states:

```dart
Widget _buildAnonymousIdCard(WidgetRef ref) {
  final asyncId = ref.watch(anonymousIdProvider);

  return Container(
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      border: Border.all(color: AppColors.border),
    ),
    child: Column(children: [
      Row(children: [
        const Icon(Icons.fingerprint, color: AppColors.textTertiary),
        const SizedBox(width: AppSpacing.sm),
        Text('Your Anonymous ID', style: AppTypography.caption),
      ]),
      const SizedBox(height: AppSpacing.sm),
      asyncId.when(
        data: (id) => Text(id, style: AppTypography.monospace),
        loading: () => const SizedBox(
          height: 16, width: 16,
          child: CircularProgressIndicator(strokeWidth: 1.5),
        ),
        error: (_, _) => Text(
          'Unable to load ID',
          style: AppTypography.caption.copyWith(color: AppColors.error),
        ),
      ),
      const SizedBox(height: AppSpacing.sm),
      Text('This ID is not linked to your identity', style: AppTypography.caption),
    ]),
  );
}
```

### 7. Reusable _SettingsTile Widget

A private `_SettingsTile` widget wraps `SurfaceCard` + `ListTile` with a leading icon box, title, optional subtitle, optional trailing widget, and optional `onTap` with chevron:

```dart
class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: ListTile(
        leading: Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          ),
          child: Icon(icon, color: AppColors.textPrimary, size: AppSpacing.iconMd),
        ),
        title: Text(title, style: AppTypography.titleSmall),
        subtitle: subtitle != null
            ? Text(subtitle!, style: AppTypography.caption) : null,
        trailing: trailing ??
            (onTap != null
                ? const Icon(Icons.chevron_right, color: AppColors.textTertiary)
                : null),
        onTap: onTap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        ),
      ),
    );
  }
}
```

## Testing
No dedicated test files were created. Manual testing required for:
- Toggle states persist during session (Riverpod state)
- Radius slider updates the km badge in real-time
- Crime type filter toggles + Select All / Deselect All
- Anonymous ID generation on first launch and persistence on subsequent launches
- Legal text screens scroll correctly with long content

## Notes
- **Deviation from plan:** No crash reporting toggle or Crashlytics integration. The plan had a `crashReportingEnabledProvider` and Firebase Crashlytics; the implementation omits this entirely.
- **Deviation from plan:** No "Clear My Data" option. The plan had a `_confirmClearData(context)` action; the implementation does not include it.
- **Deviation from plan:** No "Contact Support" email link. The implementation has a "Help & Support" tile with an empty `onTap`.
- **Deviation from plan:** Privacy section is simplified to a single "Anonymous Mode" tile with a green check icon, rather than the planned expandable privacy info dialog.
- **Addition not in plan:** Crime Type Filters section was added — lets users toggle visibility of each `ReportType` on the feed and map. These filters are consumed by `feedReportsProvider` and `mapReportsProvider`.
- **Addition not in plan:** Full legal text content (Privacy Policy and Terms of Service) is embedded in `LegalContent` class with detailed copy, navigated to via `LegalTextScreen`.
- Anonymous ID uses `SharedPreferences` + `uuid` package rather than `FlutterSecureStorage` as originally planned.
- The screen uses `SurfaceCard` for consistent card styling across all tiles.
- Bottom padding accounts for the floating nav bar via `AppSpacing.floatingNavBarSpace`.
