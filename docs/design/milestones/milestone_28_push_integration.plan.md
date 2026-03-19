# Milestone 28: Push Notification Integration

## Status
Not Started

## Goal
Integrate Firebase Cloud Messaging (FCM) into the Flutter app so users receive push notifications for nearby crime reports. Covers: Firebase project setup, permission handling, FCM token registration with the backend, foreground/background notification display, deep linking from notification tap to the relevant report, and user-facing notification preferences tied to the existing settings screen.

## Dependencies
- **Milestone 25** – `ApiClient` available for backend registration calls
- **Milestone 26** – WebSocket service for supplementary real-time updates
- **Milestone 17** – Backend deployed (will need new notification endpoints — these are a backend task but the Flutter side needs to know the contract)
- Firebase project created in Firebase Console with iOS + Android apps registered
- Existing settings providers in `lib/features/settings/providers/settings_providers.dart` (has `pushNotificationsEnabledProvider`, `notificationRadiusProvider`, `anonymousIdProvider`)

## Plan

### 1. Add Firebase Dependencies

Add to `pubspec.yaml`:

```yaml
dependencies:
  firebase_core: ^3.8.1
  firebase_messaging: ^15.2.1
```

Also requires:
- `ios/Runner/GoogleService-Info.plist` — downloaded from Firebase Console
- `android/app/google-services.json` — downloaded from Firebase Console
- Podfile update for iOS minimum deployment target (Firebase requires iOS 13+)

### 2. Firebase Initialization

Update `lib/main.dart` to initialize Firebase before `runApp`.

```dart
// lib/main.dart  (updated)

import 'package:firebase_core/firebase_core.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  await dotenv.load(fileName: '.env');
  await Firebase.initializeApp();

  // Register background message handler (must be top-level function)
  FirebaseMessaging.onBackgroundMessage(_onBackgroundMessage);

  runApp(const ProviderScope(child: CrimeReportApp()));
}

@pragma('vm:entry-point')
Future<void> _onBackgroundMessage(RemoteMessage message) async {
  await Firebase.initializeApp();
  // Background messages are handled by the system notification tray.
  // Deep linking happens when the user taps the notification (onMessageOpenedApp).
}
```

### 3. Push Notification Service

Encapsulates all FCM logic: permission request, token management, foreground display, and notification tap handling.

```dart
// lib/shared/services/push_notification_service.dart

import 'dart:async';
import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

class PushNotificationService {
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  final _tokenController = StreamController<String>.broadcast();
  Stream<String> get onTokenRefresh => _tokenController.stream;

  final _notificationTapController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get onNotificationTap => _notificationTapController.stream;

  Future<NotificationPermissionResult> requestPermission() async {
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    return switch (settings.authorizationStatus) {
      AuthorizationStatus.authorized => NotificationPermissionResult.granted,
      AuthorizationStatus.provisional => NotificationPermissionResult.granted,
      AuthorizationStatus.denied => NotificationPermissionResult.denied,
      AuthorizationStatus.notDetermined => NotificationPermissionResult.denied,
    };
  }

  Future<String?> getToken() => _messaging.getToken();

  Future<void> initialize() async {
    // Token refresh
    _messaging.onTokenRefresh.listen(_tokenController.add);

    // Foreground messages — show in-app banner
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // User tapped a notification while app was in background
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

    // App opened from terminated state via notification
    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      _handleNotificationTap(initialMessage);
    }
  }

  void _handleForegroundMessage(RemoteMessage message) {
    debugPrint('[FCM] foreground message: ${message.data}');
    // Foreground display is handled by the ForegroundNotificationBanner widget
    // which listens to FirebaseMessaging.onMessage directly.
  }

  void _handleNotificationTap(RemoteMessage message) {
    _notificationTapController.add(message.data);
  }

  Future<void> deleteToken() => _messaging.deleteToken();

  void dispose() {
    _tokenController.close();
    _notificationTapController.close();
  }
}

enum NotificationPermissionResult { granted, denied }
```

### 4. Notification Providers

Riverpod providers for initializing the service, registering the token with the backend, and handling deep links.

```dart
// lib/shared/providers/notification_providers.dart

import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:crimereport/shared/services/push_notification_service.dart';
import 'package:crimereport/shared/data/api/api_client.dart';
import 'package:crimereport/features/map/providers/map_providers.dart';
import 'package:crimereport/features/settings/providers/settings_providers.dart';

final pushServiceProvider = Provider<PushNotificationService>((ref) {
  final service = PushNotificationService();
  ref.onDispose(() => service.dispose());
  return service;
});

/// Initializes FCM, requests permission, registers token with backend.
/// Should be watched once from AppShell or CrimeReportApp.
final initNotificationsProvider = FutureProvider<void>((ref) async {
  final pushService = ref.watch(pushServiceProvider);
  final enabled = ref.watch(pushNotificationsEnabledProvider);

  if (!enabled) return;

  final permission = await pushService.requestPermission();
  if (permission == NotificationPermissionResult.denied) return;

  await pushService.initialize();

  final token = await pushService.getToken();
  if (token == null) return;

  await _registerToken(ref, token);

  // Re-register on token refresh
  pushService.onTokenRefresh.listen((newToken) => _registerToken(ref, newToken));
});

Future<void> _registerToken(Ref ref, String token) async {
  final api = ref.read(apiClientProvider);
  final position = ref.read(userLocationProvider);
  final radius = ref.read(notificationRadiusProvider);

  await api.dio.post('/api/v1/notifications/register', data: {
    'device_id': api.dio.options.headers['X-Device-ID'],
    'fcm_token': token,
    'platform': Platform.isIOS ? 'ios' : 'android',
    'lat': position?.latitude,
    'lng': position?.longitude,
    'radius_km': radius,
  });
}
```

### 5. Deep Link Handler

Navigates to the tapped report. Wired up via a provider that the root widget watches.

```dart
// lib/shared/services/deep_link_handler.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:crimereport/shared/services/push_notification_service.dart';
import 'package:crimereport/shared/providers/notification_providers.dart';

/// Global navigator key for push-notification-initiated navigation.
final navigatorKeyProvider = Provider<GlobalKey<NavigatorState>>((ref) {
  return GlobalKey<NavigatorState>();
});

/// Listens to notification taps and navigates to the relevant report.
/// Watch from the root widget to keep active.
final deepLinkProvider = Provider<void>((ref) {
  final pushService = ref.watch(pushServiceProvider);
  final navKey = ref.watch(navigatorKeyProvider);

  pushService.onNotificationTap.listen((data) {
    final reportId = data['report_id'] as String?;
    if (reportId == null) return;

    // Navigate to the feed focused on this report.
    // The exact navigation depends on the app's routing setup.
    // For now, switch to feed tab and scroll to report.
    navKey.currentState?.pushNamed('/report/$reportId');
  });
});
```

### 6. Foreground Notification Banner

An in-app banner that slides down when a notification arrives while the app is in the foreground. Less intrusive than a system notification.

```dart
// lib/shared/widgets/foreground_notification_banner.dart

import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:crimereport/core/theme/theme.dart';

class ForegroundNotificationBanner extends StatefulWidget {
  final Widget child;
  const ForegroundNotificationBanner({super.key, required this.child});

  @override
  State<ForegroundNotificationBanner> createState() => _ForegroundNotificationBannerState();
}

class _ForegroundNotificationBannerState extends State<ForegroundNotificationBanner> {
  StreamSubscription? _sub;
  RemoteMessage? _currentMessage;

  @override
  void initState() {
    super.initState();
    _sub = FirebaseMessaging.onMessage.listen((message) {
      if (message.notification == null) return;
      setState(() => _currentMessage = message);
      Future.delayed(const Duration(seconds: 4), () {
        if (mounted && _currentMessage == message) {
          setState(() => _currentMessage = null);
        }
      });
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_currentMessage != null)
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 16,
            right: 16,
            child: GestureDetector(
              onTap: () {
                setState(() => _currentMessage = null);
                // Could navigate to report here
              },
              child: Material(
                elevation: 6,
                borderRadius: BorderRadius.circular(12),
                color: AppColors.surface,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 24),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _currentMessage!.notification!.title ?? 'Crime Alert',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            if (_currentMessage!.notification!.body != null)
                              Text(
                                _currentMessage!.notification!.body!,
                                style: TextStyle(color: Colors.grey[400], fontSize: 12),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
```

### 7. Update Settings Screen

Wire the existing `pushNotificationsEnabledProvider` and `notificationRadiusProvider` to actually register/unregister with the backend when toggled.

```dart
// lib/features/settings/providers/settings_providers.dart  (additions)

/// When push notifications toggle changes, update the backend.
void setPushNotificationsEnabled(WidgetRef ref, bool enabled) async {
  ref.read(pushNotificationsEnabledProvider.notifier).state = enabled;

  final api = ref.read(apiClientProvider);
  if (!enabled) {
    // Unregister: tell backend to stop sending to this device
    await api.dio.post('/api/v1/notifications/unregister', data: {
      'device_id': api.dio.options.headers['X-Device-ID'],
    });
    // Optionally delete FCM token locally
    await ref.read(pushServiceProvider).deleteToken();
  } else {
    // Re-register
    ref.invalidate(initNotificationsProvider);
  }
}

/// When notification radius changes, update the backend registration.
void setNotificationRadius(WidgetRef ref, double radiusKm) async {
  ref.read(notificationRadiusProvider.notifier).state = radiusKm;

  final api = ref.read(apiClientProvider);
  final token = await ref.read(pushServiceProvider).getToken();
  if (token == null) return;

  final position = ref.read(userLocationProvider);
  await api.dio.post('/api/v1/notifications/register', data: {
    'device_id': api.dio.options.headers['X-Device-ID'],
    'fcm_token': token,
    'platform': Platform.isIOS ? 'ios' : 'android',
    'lat': position?.latitude,
    'lng': position?.longitude,
    'radius_km': radiusKm,
  });
}
```

### 8. Wire Up in App

```dart
// lib/app.dart  (updated)

class CrimeReportApp extends ConsumerWidget {
  const CrimeReportApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Initialize push notifications
    ref.watch(initNotificationsProvider);
    // Wire deep link handler
    ref.watch(deepLinkProvider);

    final navKey = ref.watch(navigatorKeyProvider);

    SystemChrome.setSystemUIOverlayStyle(/* ... existing ... */);

    return MaterialApp(
      navigatorKey: navKey,
      title: 'CrImEreport',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const ForegroundNotificationBanner(child: AppShell()),
    );
  }
}
```

## Backend API Contract (reference)

These endpoints need to exist on the backend (separate backend milestone). The Flutter code above assumes:

| Method | Path | Body | Description |
|--------|------|------|-------------|
| POST | `/api/v1/notifications/register` | `{ device_id, fcm_token, platform, lat, lng, radius_km }` | Register/update FCM token |
| POST | `/api/v1/notifications/unregister` | `{ device_id }` | Remove device registration |

The backend sends push notifications via FCM with this payload shape:

```json
{
  "notification": {
    "title": "Theft reported nearby",
    "body": "A theft was reported 0.3 km from you"
  },
  "data": {
    "type": "new_report",
    "report_id": "uuid-here"
  }
}
```

## Testing Plan

- **Unit tests** for `PushNotificationService` — mock `FirebaseMessaging`, verify `requestPermission` returns correct enum, verify `getToken` is called.
- **Unit tests** for `_registerToken` — mock `ApiClient`, verify POST body includes all fields.
- **Unit tests** for deep link handler — push data through `onNotificationTap` stream, verify navigation.
- **Widget tests** for `ForegroundNotificationBanner` — inject a `RemoteMessage`, verify banner appears and auto-dismisses.
- **Widget tests** for settings toggle — verify `setPushNotificationsEnabled(false)` calls unregister endpoint.
- **Integration test** (manual) — send a test FCM message from Firebase Console, verify it appears as a banner in-app and in the system tray when backgrounded. Tap the notification, verify it navigates to the report.

## Notes

- **New dependencies:** `firebase_core` and `firebase_messaging` need to be added to pubspec.yaml. These also require native setup (GoogleService-Info.plist for iOS, google-services.json for Android, CocoaPods update).
- **No `flutter_local_notifications` needed** — Firebase Messaging handles background notifications natively. For foreground, we use a custom in-app banner (`ForegroundNotificationBanner`) which is simpler and fits the dark theme.
- **Existing settings providers** — `pushNotificationsEnabledProvider` and `notificationRadiusProvider` already exist in `settings_providers.dart`. This milestone wires them to actual backend calls instead of being local-only state.
- **`anonymousIdProvider`** serves as the device identifier for FCM registration, consistent with the REST API's `X-Device-ID` header.
- **Background message handler** must be a top-level function (Dart isolate requirement). It only needs to call `Firebase.initializeApp()` — the system tray handles display.
- **Deep linking** — the exact routing mechanism depends on whether we add named routes or a router package later. The initial implementation uses `GlobalKey<NavigatorState>` which is straightforward.
- **Android notification channel** — Firebase Messaging auto-creates a default channel. A custom high-importance channel can be added later for finer control.
- **Automatic location re-registration** — The app should silently re-register with the backend when the user moves to a new area so the `push_subscriptions` table stays current. Use the platform's "significant location change" API (iOS: `CLLocationManager.startMonitoringSignificantLocationChanges`, Android: `FusedLocationProviderClient` with `PRIORITY_BALANCED_POWER_ACCURACY`) which fires only when the user moves ~500m+. This balances accuracy with battery life. On each significant location change, call `POST /api/v1/notifications/register` with the updated lat/lng — the backend's `upsert` query handles updating the existing row. Avoid high-frequency GPS polling (battery drain) or only-on-app-open registration (stale location data).

## Files

| # | Path | Action |
|---|------|--------|
| 1 | `lib/shared/services/push_notification_service.dart` | Create |
| 2 | `lib/shared/providers/notification_providers.dart` | Create |
| 3 | `lib/shared/services/deep_link_handler.dart` | Create |
| 4 | `lib/shared/widgets/foreground_notification_banner.dart` | Create |
| 5 | `lib/main.dart` | Modify — add Firebase.initializeApp, background handler |
| 6 | `lib/app.dart` | Modify — watch initNotificationsProvider, add navigatorKey, wrap with banner |
| 7 | `lib/features/settings/providers/settings_providers.dart` | Modify — add backend sync functions |
| 8 | `lib/features/settings/presentation/settings_screen.dart` | Modify — wire toggle/radius to new sync functions |
| 9 | `pubspec.yaml` | Modify — add firebase_core, firebase_messaging |
| 10 | `ios/Runner/GoogleService-Info.plist` | Create — from Firebase Console |
| 11 | `android/app/google-services.json` | Create — from Firebase Console |
