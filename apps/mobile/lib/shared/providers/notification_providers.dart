import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:crimereport/shared/data/api/api_client.dart';
import 'package:crimereport/shared/services/push_notification_service.dart';
import 'package:crimereport/features/map/providers/map_providers.dart';
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

  final token = await pushService.getDeviceToken();
  if (token != null) {
    await _registerToken(ref, token);
  }

  // FCM `onTokenRefresh` only fires when the FCM token rotates. On iOS we
  // still need to send the APNs token to SNS, so re-resolve via
  // `getDeviceToken()` instead of trusting the FCM-shaped event payload.
  pushService.onTokenRefresh.listen((_) async {
    final refreshed = await pushService.getDeviceToken();
    if (refreshed != null) {
      await _registerToken(ref, refreshed);
    }
  });
});

// ---------------------------------------------------------------------------
// Token registration helper
// ---------------------------------------------------------------------------

Future<void> _registerToken(Ref ref, String token) async {
  try {
    // Backend registerDeviceSchema requires device_id and non-null
    // numeric lat/lng, so we must have both a persisted anonymous ID and
    // a real GPS location before calling /register.
    final deviceId = await ref.read(anonymousIdProvider.future);
    final locationService = ref.read(locationServiceProvider);
    final position = await locationService.getCurrentPosition();

    if (position == null) {
      debugPrint(
        'Skipping push registration: GPS location unavailable',
      );
      return;
    }

    final apiClient = ref.read(apiClientProvider);
    await apiClient.post(
      '/api/v1/notifications/register',
      data: {
        'device_id': deviceId,
        'fcm_token': token,
        'platform': _platformName,
        'lat': position.latitude,
        'lng': position.longitude,
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
