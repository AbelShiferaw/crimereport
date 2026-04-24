import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'package:crimereport/core/constants/enums.dart';
import 'package:crimereport/shared/data/api/api_client.dart';
import 'package:crimereport/shared/providers/notification_providers.dart';

/// Whether push notifications are enabled.
final pushNotificationsEnabledProvider = StateProvider<bool>((ref) => true);

/// Notification radius in kilometers (1-50 km).
final notificationRadiusProvider = StateProvider<double>((ref) => 10.0);

/// Set of active crime type filters. Defaults to all types enabled.
final crimeTypeFiltersProvider = StateProvider<Set<ReportType>>(
  (ref) => Set.from(ReportType.values),
);

const _anonymousIdKey = 'anonymous_device_id';

/// Persisted anonymous device ID, generated once on first launch.
final anonymousIdProvider = FutureProvider<String>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  final existing = prefs.getString(_anonymousIdKey);
  if (existing != null) return existing;

  final newId = const Uuid().v4();
  await prefs.setString(_anonymousIdKey, newId);
  return newId;
});

// ---------------------------------------------------------------------------
// Push notification sync helpers
// ---------------------------------------------------------------------------

Future<void> setPushNotificationsEnabled(WidgetRef ref, bool enabled) async {
  ref.read(pushNotificationsEnabledProvider.notifier).state = enabled;

  if (!enabled) {
    try {
      // Backend unregisterDeviceSchema requires `{ device_id }` in the
      // body. Previous versions sent no body, causing a 400.
      final deviceId = await ref.read(anonymousIdProvider.future);
      final apiClient = ref.read(apiClientProvider);
      await apiClient.delete(
        '/api/v1/notifications/unregister',
        data: {'device_id': deviceId},
      );
    } catch (e) {
      debugPrint('Failed to unregister notifications: $e');
    }

    try {
      final pushService = ref.read(pushServiceProvider);
      await pushService.deleteToken();
    } catch (e) {
      debugPrint('Failed to delete FCM token: $e');
    }
  } else {
    ref.invalidate(initNotificationsProvider);
  }
}

Future<void> setNotificationRadius(WidgetRef ref, double radiusKm) async {
  ref.read(notificationRadiusProvider.notifier).state = radiusKm;

  final pushEnabled = ref.read(pushNotificationsEnabledProvider);
  if (!pushEnabled) return;

  try {
    // Backend updatePreferencesSchema: PUT /preferences with
    // { device_id, radius? (int meters, 1000-50000), types?, enabled? }.
    // Previous code POSTed to /register with a malformed payload.
    final deviceId = await ref.read(anonymousIdProvider.future);
    final apiClient = ref.read(apiClientProvider);
    final radiusMeters = (radiusKm * 1000).round().clamp(1000, 50000);

    await apiClient.put(
      '/api/v1/notifications/preferences',
      data: {
        'device_id': deviceId,
        'radius': radiusMeters,
      },
    );
  } catch (e) {
    debugPrint('Failed to update notification radius: $e');
  }
}
