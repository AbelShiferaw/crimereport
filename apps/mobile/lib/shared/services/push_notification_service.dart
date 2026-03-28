import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

// ---------------------------------------------------------------------------
// Permission result
// ---------------------------------------------------------------------------

enum NotificationPermissionResult { granted, denied }

// ---------------------------------------------------------------------------
// Push notification service
// ---------------------------------------------------------------------------

class PushNotificationService {
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  final _tokenRefreshController = StreamController<String>.broadcast();
  final _notificationTapController =
      StreamController<Map<String, dynamic>>.broadcast();

  StreamSubscription<String>? _tokenSub;
  StreamSubscription<RemoteMessage>? _foregroundSub;

  Stream<String> get onTokenRefresh => _tokenRefreshController.stream;
  Stream<Map<String, dynamic>> get onNotificationTap =>
      _notificationTapController.stream;

  // ---- Permission ----

  Future<NotificationPermissionResult> requestPermission() async {
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    final status = settings.authorizationStatus;
    if (status == AuthorizationStatus.authorized ||
        status == AuthorizationStatus.provisional) {
      return NotificationPermissionResult.granted;
    }
    return NotificationPermissionResult.denied;
  }

  // ---- Token ----

  Future<String?> getToken() async {
    try {
      return await _messaging.getToken();
    } catch (e) {
      debugPrint('Failed to get FCM token: $e');
      return null;
    }
  }

  Future<void> deleteToken() async {
    try {
      await _messaging.deleteToken();
    } catch (e) {
      debugPrint('Failed to delete FCM token: $e');
    }
  }

  // ---- Initialize ----

  Future<void> initialize() async {
    _tokenSub = _messaging.onTokenRefresh.listen((token) {
      _tokenRefreshController.add(token);
    });

    _foregroundSub = FirebaseMessaging.onMessage.listen((message) {
      debugPrint('Foreground message: ${message.messageId}');
    });

    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      _notificationTapController.add(message.data);
    });

    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      _notificationTapController.add(initialMessage.data);
    }
  }

  // ---- Cleanup ----

  void dispose() {
    _tokenSub?.cancel();
    _foregroundSub?.cancel();
    _tokenRefreshController.close();
    _notificationTapController.close();
  }
}
