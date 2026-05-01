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
  PushNotificationService({
    FirebaseMessaging? messaging,
    TargetPlatform Function()? platformOverride,
  })  : _messaging = messaging ?? FirebaseMessaging.instance,
        _platformOverride = platformOverride;

  final FirebaseMessaging _messaging;
  final TargetPlatform Function()? _platformOverride;

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

  /// Returns the FCM token. Use [getDeviceToken] for cross-platform
  /// registration that returns the APNs token on iOS.
  Future<String?> getToken() async {
    try {
      return await _messaging.getToken();
    } catch (e) {
      debugPrint('Failed to get FCM token: $e');
      return null;
    }
  }

  /// Returns the device-appropriate push token for backend registration:
  ///
  /// - On iOS, the raw APNs device token via [FirebaseMessaging.getAPNSToken],
  ///   retrying every [pollInterval] for up to [maxAttempts] times because
  ///   APNs registration is asynchronous after app launch and the token may
  ///   be `null` for the first few hundred milliseconds. Returns `null` if
  ///   the token never becomes available.
  /// - On Android (and other platforms including web), the FCM token via
  ///   [getToken].
  ///
  /// AWS SNS expects an APNs hex token for the iOS platform application;
  /// sending an FCM token there yields an `InvalidParameterException`.
  Future<String?> getDeviceToken({
    Duration pollInterval = const Duration(milliseconds: 500),
    int maxAttempts = 20,
  }) async {
    final platform = _currentPlatform();
    if (platform == TargetPlatform.iOS) {
      return _getApnsTokenWithRetry(
        pollInterval: pollInterval,
        maxAttempts: maxAttempts,
      );
    }
    // Android, web, and any other platform: use the FCM token.
    return getToken();
  }

  Future<String?> _getApnsTokenWithRetry({
    required Duration pollInterval,
    required int maxAttempts,
  }) async {
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        final token = await _messaging.getAPNSToken();
        if (token != null && token.isNotEmpty) {
          return token;
        }
      } catch (e) {
        debugPrint('Failed to get APNs token (attempt ${attempt + 1}): $e');
      }
      if (attempt < maxAttempts - 1) {
        await Future<void>.delayed(pollInterval);
      }
    }
    debugPrint(
      'APNs token not available after $maxAttempts attempts; '
      'skipping push registration for this launch',
    );
    return null;
  }

  TargetPlatform? _currentPlatform() {
    if (kIsWeb) return null;
    final override = _platformOverride;
    if (override != null) return override();
    return defaultTargetPlatform;
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
