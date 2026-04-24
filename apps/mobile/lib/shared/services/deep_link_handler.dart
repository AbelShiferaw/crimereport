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

    // Use an imperative MaterialPageRoute rather than pushNamed: the
    // MaterialApp in app.dart defines no named routes, so pushNamed
    // would throw a "Could not find a generator for route" error and
    // crash the notification-tap flow.
    //
    // A dedicated ReportDetailScreen is out of scope for milestone 31;
    // the placeholder Scaffold below ensures taps open cleanly and
    // leaves an obvious extension point for future work.
    navigator.push(
      MaterialPageRoute(
        builder: (_) => _ReportDeepLinkPlaceholder(reportId: reportId),
      ),
    );
  });

  ref.onDispose(() => sub.cancel());
});

class _ReportDeepLinkPlaceholder extends StatelessWidget {
  final String reportId;

  const _ReportDeepLinkPlaceholder({required this.reportId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Report')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Report ID: $reportId',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
