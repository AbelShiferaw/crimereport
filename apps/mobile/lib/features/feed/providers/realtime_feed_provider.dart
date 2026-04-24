import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:crimereport/core/constants/enums.dart';
import 'package:crimereport/features/feed/data/models/report.dart';
import 'package:crimereport/shared/data/websocket/websocket_service.dart';
import 'package:crimereport/shared/data/websocket/ws_events.dart';

class RealtimeFeedNotifier extends StateNotifier<List<Report>> {
  final WebSocketService _ws;
  StreamSubscription<ReportEvent>? _sub;

  int _newCount = 0;
  int get newCount => _newCount;

  RealtimeFeedNotifier(this._ws) : super([]) {
    _sub = _ws.reportEvents.listen(_onEvent);
  }

  void seed(List<Report> reports) {
    state = reports;
    _newCount = 0;
  }

  void resetNewCount() => _newCount = 0;

  void _onEvent(ReportEvent event) {
    switch (event) {
      case NewReportEvent():
        final report = Report(
          id: event.id,
          deviceId: '',
          type: event.type,
          description: event.description,
          latitude: event.lat,
          longitude: event.lng,
          media: [],
          upvotes: event.upvotes,
          commentCount: event.commentCount,
          createdAt: event.createdAt,
          status: ReportStatus.active,
        );
        state = [report, ...state];
        _newCount++;

      case UpvoteUpdateEvent():
        state = [
          for (final r in state)
            if (r.id == event.reportId)
              r.copyWith(
                upvotes: event.upvoted ? r.upvotes + 1 : r.upvotes - 1,
              )
            else
              r,
        ];

      case MediaReadyEvent():
        break;
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

final realtimeFeedProvider =
    StateNotifierProvider<RealtimeFeedNotifier, List<Report>>((ref) {
  final ws = ref.watch(wsServiceProvider);
  return RealtimeFeedNotifier(ws);
});
