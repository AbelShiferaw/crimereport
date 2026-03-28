import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:crimereport/shared/providers/notification_providers.dart';

// ---------------------------------------------------------------------------
// Navigator key provider
// ---------------------------------------------------------------------------

final navigatorKeyProvider = Provider<GlobalKey<NavigatorState>>((ref) {
  return GlobalKey<NavigatorState>();
});

// ---------------------------------------------------------------------------
// Deep link provider
// ---------------------------------------------------------------------------

final deepLinkProvider = Provider<void>((ref) {
  final pushService = ref.watch(pushServiceProvider);
  final navigatorKey = ref.watch(navigatorKeyProvider);

  late final StreamSubscription<Map<String, dynamic>> sub;
  sub = pushService.onNotificationTap.listen((data) {
    final reportId = data['report_id'] as String?;
    if (reportId == null) return;

    final navigator = navigatorKey.currentState;
    if (navigator == null) return;

    navigator.pushNamed('/report/$reportId');
  });

  ref.onDispose(() => sub.cancel());
});
