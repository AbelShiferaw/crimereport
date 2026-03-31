import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:crimereport/shared/data/api/api_client.dart';
import 'package:crimereport/shared/services/push_notification_service.dart';
import 'package:crimereport/features/settings/providers/settings_providers.dart';

// ---------------------------------------------------------------------------
// Push service provider
// ---------------------------------------------------------------------------

final pushServiceProvider = Provider<PushNotificationService>((ref) {
  final service = PushNotificationService();
  ref.onDispose(() => service.dispose());
  return service;
});

// ---------------------------------------------------------------------------
// Init notifications provider
// ---------------------------------------------------------------------------

final initNotificationsProvider = FutureProvider<void>((ref) async {
  final pushEnabled = ref.watch(pushNotificationsEnabledProvider);
  if (!pushEnabled) return;

  final pushService = ref.read(pushServiceProvider);

  final permission = await pushService.requestPermission();
  if (permission == NotificationPermissionResult.denied) return;

  await pushService.initialize();

  final token = await pushService.getToken();
  if (token != null) {
    await _registerToken(ref, token);
  }

  pushService.onTokenRefresh.listen((newToken) {
    _registerToken(ref, newToken);
  });
});

// ---------------------------------------------------------------------------
// Token registration helper
// ---------------------------------------------------------------------------

Future<void> _registerToken(Ref ref, String token) async {
  try {
    final apiClient = ref.read(apiClientProvider);
    final radius = ref.read(notificationRadiusProvider);

    await apiClient.post(
      '/api/v1/notifications/register',
      data: {
        'fcm_token': token,
        'platform': _platformName,
        'lat': null,
        'lng': null,
        'radius_km': radius,
      },
    );
  } catch (e) {
    debugPrint('Failed to register FCM token: $e');
  }
}

String get _platformName {
  if (kIsWeb) return 'web';
  try {
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
  } catch (_) {}
  return 'unknown';
}
