# Milestone 12: Settings Screen

## Goal
Build the settings screen with notification preferences, privacy info, and app information.

## Dependencies
Requires **Milestone 1** complete (project structure).

## Implementation

### 1. Settings Screen
```dart
// lib/features/settings/presentation/settings_screen.dart
class SettingsScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFF121212),
      appBar: AppBar(
        title: Text('Settings'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        children: [
          // Notifications section
          _SectionHeader(title: 'Notifications'),
          _SettingsTile(
            icon: Icons.notifications_outlined,
            title: 'Push Notifications',
            subtitle: 'Get alerts for nearby crimes',
            trailing: _NotificationToggle(),
          ),
          _SettingsTile(
            icon: Icons.location_on_outlined,
            title: 'Alert Radius',
            subtitle: '5 miles',
            onTap: () => _showRadiusPicker(context),
          ),
          
          Divider(color: Colors.grey[800], height: 32),
          
          // Privacy section
          _SectionHeader(title: 'Privacy'),
          _SettingsTile(
            icon: Icons.shield_outlined,
            title: 'How We Protect You',
            subtitle: 'Learn about our anonymity features',
            onTap: () => _showPrivacyInfo(context),
          ),
          _SettingsTile(
            icon: Icons.delete_outline,
            title: 'Clear My Data',
            subtitle: 'Delete all local data',
            onTap: () => _confirmClearData(context),
          ),
          
          Divider(color: Colors.grey[800], height: 32),
          
          // About section
          _SectionHeader(title: 'About'),
          _SettingsTile(
            icon: Icons.info_outline,
            title: 'App Version',
            subtitle: '1.0.0 (Build 1)',
          ),
          _SettingsTile(
            icon: Icons.description_outlined,
            title: 'Terms of Service',
            onTap: () => _openUrl('https://...'),
          ),
          _SettingsTile(
            icon: Icons.privacy_tip_outlined,
            title: 'Privacy Policy',
            onTap: () => _openUrl('https://...'),
          ),
          _SettingsTile(
            icon: Icons.email_outlined,
            title: 'Contact Support',
            onTap: () => _openUrl('mailto:support@...'),
          ),
          
          SizedBox(height: 32),
          
          // Anonymous ID display
          _AnonymousIdCard(),
        ],
      ),
    );
  }
}
```

### 2. Settings Tile Widget
```dart
class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  
  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.grey[800],
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
      title: Text(
        title,
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
      ),
      subtitle: subtitle != null
          ? Text(subtitle!, style: TextStyle(color: Colors.grey))
          : null,
      trailing: trailing ?? (onTap != null
          ? Icon(Icons.chevron_right, color: Colors.grey)
          : null),
      onTap: onTap,
    );
  }
}
```

### 3. Notification Toggle
```dart
class _NotificationToggle extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(notificationsEnabledProvider);
    
    return Switch(
      value: enabled,
      onChanged: (value) {
        ref.read(notificationsEnabledProvider.notifier).state = value;
        // TODO: Register/unregister FCM token
      },
      activeColor: Colors.red,
    );
  }
}
```

### 4. Anonymous ID Card
```dart
class _AnonymousIdCard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deviceId = ref.watch(deviceIdProvider);
    
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 16),
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[800]!),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.fingerprint, color: Colors.grey),
              SizedBox(width: 12),
              Text(
                'Your Anonymous ID',
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
          SizedBox(height: 8),
          Text(
            deviceId.substring(0, 16) + '...',
            style: TextStyle(
              color: Colors.white,
              fontFamily: 'monospace',
              fontSize: 12,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'This ID is not linked to your identity',
            style: TextStyle(color: Colors.grey, fontSize: 11),
          ),
        ],
      ),
    );
  }
}
```

### 5. Privacy Info Dialog
```dart
void _showPrivacyInfo(BuildContext context) {
  showDialog(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: Color(0xFF1E1E1E),
      title: Text('Your Privacy', style: TextStyle(color: Colors.white)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PrivacyPoint(
            icon: Icons.visibility_off,
            text: 'No account required',
          ),
          _PrivacyPoint(
            icon: Icons.location_off,
            text: 'Your exact location is never stored',
          ),
          _PrivacyPoint(
            icon: Icons.person_off,
            text: 'Reports cannot be traced to you',
          ),
          _PrivacyPoint(
            icon: Icons.delete_forever,
            text: 'You can delete your data anytime',
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Got it', style: TextStyle(color: Colors.red)),
        ),
      ],
    ),
  );
}
```

## Deliverable Checklist
- [ ] Settings screen displays all sections
- [ ] Notification toggle works (saves preference)
- [ ] Alert radius picker shows options
- [ ] Privacy info dialog explains anonymity
- [ ] Clear data shows confirmation
- [ ] App version displays correctly
- [ ] External links open (Terms, Privacy, Support)
- [ ] Anonymous ID displayed (hashed)
- [ ] Clean, consistent styling

## Files (3 total)
1. `lib/features/settings/presentation/settings_screen.dart` - Update
2. `lib/features/settings/presentation/widgets/settings_tile.dart` - Create
3. `lib/shared/providers/settings_providers.dart` - Create (notification prefs)
