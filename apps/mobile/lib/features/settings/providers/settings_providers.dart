import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'package:crimereport/core/constants/enums.dart';

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
