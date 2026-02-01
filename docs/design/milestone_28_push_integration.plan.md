# Milestone 28: Push Notification Integration

## Goal
Integrate Firebase Cloud Messaging in Flutter app for receiving nearby crime alerts.

## Dependencies
Requires **Milestone 24** (push notification backend) and Firebase project setup.

## Implementation

### 1. Firebase Setup

**pubspec.yaml additions:**
```yaml
dependencies:
  firebase_core: ^2.24.2
  firebase_messaging: ^14.7.10
```

**iOS Setup** (`ios/Runner/AppDelegate.swift`):
```swift
import UIKit
import Flutter
import FirebaseCore
import FirebaseMessaging

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    FirebaseApp.configure()
    
    // Request notification permission
    UNUserNotificationCenter.current().delegate = self
    
    let authOptions: UNAuthorizationOptions = [.alert, .badge, .sound]
    UNUserNotificationCenter.current().requestAuthorization(
      options: authOptions,
      completionHandler: { _, _ in }
    )
    
    application.registerForRemoteNotifications()
    
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
```

### 2. Push Notification Service
```dart
// lib/shared/services/push_notification_service.dart

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class PushNotificationService {
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  
  final _tokenController = StreamController<String>.broadcast();
  Stream<String> get tokenStream => _tokenController.stream;
  
  Future<void> initialize() async {
    // Request permission
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    
    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      print('Push notifications authorized');
      await _setupNotifications();
    }
  }
  
  Future<void> _setupNotifications() async {
    // Get FCM token
    final token = await _messaging.getToken();
    if (token != null) {
      _tokenController.add(token);
    }
    
    // Listen for token refresh
    _messaging.onTokenRefresh.listen(_tokenController.add);
    
    // Initialize local notifications (for foreground)
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    
    await _localNotifications.initialize(
      InitializationSettings(android: androidSettings, iOS: iosSettings),
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );
    
    // Create notification channel (Android)
    const channel = AndroidNotificationChannel(
      'crime_alerts',
      'Crime Alerts',
      description: 'Notifications for nearby crime reports',
      importance: Importance.high,
    );
    
    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
    
    // Handle foreground messages
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
    
    // Handle background message tap
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpenedApp);
    
    // Handle app opened from terminated state
    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      _handleMessageOpenedApp(initialMessage);
    }
  }
  
  void _handleForegroundMessage(RemoteMessage message) {
    final notification = message.notification;
    final data = message.data;
    
    if (notification != null) {
      // Show local notification
      _localNotifications.show(
        notification.hashCode,
        notification.title,
        notification.body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            'crime_alerts',
            'Crime Alerts',
            icon: '@mipmap/ic_launcher',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        payload: json.encode(data),
      );
    }
  }
  
  void _handleMessageOpenedApp(RemoteMessage message) {
    final data = message.data;
    
    if (data['type'] == 'NEW_REPORT' && data['reportId'] != null) {
      // Navigate to report
      _navigateToReport(data['reportId']);
    }
  }
  
  void _onNotificationTapped(NotificationResponse response) {
    if (response.payload != null) {
      final data = json.decode(response.payload!);
      if (data['type'] == 'NEW_REPORT' && data['reportId'] != null) {
        _navigateToReport(data['reportId']);
      }
    }
  }
  
  void _navigateToReport(String reportId) {
    // Use navigator key to navigate
    NavigationService.navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => ReportDetailScreen(reportId: reportId),
      ),
    );
  }
  
  Future<String?> getToken() => _messaging.getToken();
}
```

### 3. Register Device with Backend
```dart
// lib/shared/providers/notification_providers.dart

final pushNotificationServiceProvider = Provider<PushNotificationService>((ref) {
  final service = PushNotificationService();
  return service;
});

final registerPushNotificationsProvider = FutureProvider<void>((ref) async {
  final pushService = ref.watch(pushNotificationServiceProvider);
  final api = ref.watch(apiClientProvider);
  final location = await ref.watch(userLocationProvider.future);
  
  await pushService.initialize();
  
  final token = await pushService.getToken();
  if (token == null) return;
  
  // Determine platform
  final platform = Platform.isIOS ? 'ios' : 'android';
  
  // Register with backend
  await api.post('/api/v1/notifications/register', data: {
    'fcmToken': token,
    'platform': platform,
    'latitude': location.latitude,
    'longitude': location.longitude,
  });
  
  // Listen for token refresh
  pushService.tokenStream.listen((newToken) async {
    await api.post('/api/v1/notifications/register', data: {
      'fcmToken': newToken,
      'platform': platform,
      'latitude': location.latitude,
      'longitude': location.longitude,
    });
  });
});
```

### 4. Notification Settings Screen Update
```dart
// lib/features/settings/presentation/settings_screen.dart (additions)

class _NotificationSettingsSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(notificationPreferencesProvider);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(title: 'Notifications'),
        
        // Enable/disable toggle
        SwitchListTile(
          title: Text('Push Notifications'),
          subtitle: Text('Get alerts for nearby crimes'),
          value: prefs.enabled,
          onChanged: (value) {
            ref.read(notificationPreferencesProvider.notifier)
                .setEnabled(value);
          },
        ),
        
        if (prefs.enabled) ...[
          // Alert radius
          ListTile(
            title: Text('Alert Radius'),
            subtitle: Text('${(prefs.radius / 1000).round()} km'),
            trailing: Icon(Icons.chevron_right),
            onTap: () => _showRadiusPicker(context, ref),
          ),
          
          // Crime types
          ListTile(
            title: Text('Crime Types'),
            subtitle: Text(
              prefs.types.isEmpty 
                  ? 'All types'
                  : prefs.types.map((t) => t.displayName).join(', ')
            ),
            trailing: Icon(Icons.chevron_right),
            onTap: () => _showTypePicker(context, ref),
          ),
        ],
      ],
    );
  }
  
  void _showRadiusPicker(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      builder: (_) => RadiusPickerSheet(
        currentRadius: ref.read(notificationPreferencesProvider).radius,
        onSelected: (radius) {
          ref.read(notificationPreferencesProvider.notifier)
              .setRadius(radius);
          Navigator.pop(context);
        },
      ),
    );
  }
}
```

### 5. Notification Preferences Provider
```dart
// lib/shared/providers/notification_preferences_provider.dart

class NotificationPreferences {
  final bool enabled;
  final int radius; // meters
  final List<ReportType> types;
  
  NotificationPreferences({
    this.enabled = true,
    this.radius = 10000,
    this.types = const [],
  });
}

final notificationPreferencesProvider = StateNotifierProvider<
    NotificationPreferencesNotifier, NotificationPreferences>((ref) {
  return NotificationPreferencesNotifier(ref);
});

class NotificationPreferencesNotifier extends StateNotifier<NotificationPreferences> {
  final Ref _ref;
  
  NotificationPreferencesNotifier(this._ref) : super(NotificationPreferences()) {
    _loadPreferences();
  }
  
  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    state = NotificationPreferences(
      enabled: prefs.getBool('notifications_enabled') ?? true,
      radius: prefs.getInt('notifications_radius') ?? 10000,
      types: (prefs.getStringList('notifications_types') ?? [])
          .map((t) => ReportType.values.firstWhere((e) => e.name == t))
          .toList(),
    );
  }
  
  Future<void> setEnabled(bool enabled) async {
    state = NotificationPreferences(
      enabled: enabled,
      radius: state.radius,
      types: state.types,
    );
    
    // Update backend
    final api = _ref.read(apiClientProvider);
    await api.put('/api/v1/notifications/preferences', data: {
      'enabled': enabled,
    });
    
    // Save locally
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notifications_enabled', enabled);
  }
  
  Future<void> setRadius(int radius) async {
    state = NotificationPreferences(
      enabled: state.enabled,
      radius: radius,
      types: state.types,
    );
    
    final api = _ref.read(apiClientProvider);
    await api.put('/api/v1/notifications/preferences', data: {
      'radius': radius,
    });
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('notifications_radius', radius);
  }
  
  Future<void> setTypes(List<ReportType> types) async {
    state = NotificationPreferences(
      enabled: state.enabled,
      radius: state.radius,
      types: types,
    );
    
    final api = _ref.read(apiClientProvider);
    await api.put('/api/v1/notifications/preferences', data: {
      'types': types.map((t) => t.name).toList(),
    });
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      'notifications_types',
      types.map((t) => t.name).toList(),
    );
  }
}
```

### 6. Initialize in App
```dart
// lib/main.dart

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  
  runApp(
    ProviderScope(
      child: ReportCrimeApp(),
    ),
  );
}

// lib/app.dart
class ReportCrimeApp extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Initialize push notifications
    ref.watch(registerPushNotificationsProvider);
    
    return MaterialApp(
      navigatorKey: NavigationService.navigatorKey,
      // ...
    );
  }
}
```

## Deliverable Checklist
- [ ] Firebase configured for iOS and Android
- [ ] Permission request shows on first launch
- [ ] FCM token obtained and sent to backend
- [ ] Token refresh handled
- [ ] Foreground notifications display
- [ ] Tapping notification opens report
- [ ] Background notifications work
- [ ] App opened from terminated state handles notification
- [ ] Settings toggle enables/disables
- [ ] Radius picker updates backend
- [ ] Crime type filter works
- [ ] Preferences persisted locally

## Files (6 total)
1. `lib/shared/services/push_notification_service.dart` - Create
2. `lib/shared/providers/notification_providers.dart` - Create
3. `lib/shared/providers/notification_preferences_provider.dart` - Create
4. `lib/features/settings/presentation/settings_screen.dart` - Update
5. `lib/main.dart` - Update with Firebase init
6. `pubspec.yaml` - Add Firebase dependencies
