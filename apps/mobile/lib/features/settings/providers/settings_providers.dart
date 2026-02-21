import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/enums.dart';

/// Whether push notifications are enabled.
final pushNotificationsEnabledProvider = StateProvider<bool>((ref) => true);

/// Notification radius in kilometers (1-50 km).
final notificationRadiusProvider = StateProvider<double>((ref) => 10.0);

/// Set of active crime type filters. Defaults to all types enabled.
final crimeTypeFiltersProvider = StateProvider<Set<ReportType>>(
  (ref) => Set.from(ReportType.values),
);
