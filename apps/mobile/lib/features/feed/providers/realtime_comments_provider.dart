import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:crimereport/features/feed/data/models/comment.dart';
import 'package:crimereport/shared/data/websocket/websocket_service.dart';
import 'package:crimereport/shared/data/websocket/ws_events.dart';

class RealtimeCommentsNotifier extends StateNotifier<List<Comment>> {
  final WebSocketService _ws;
  final String _reportId;
  StreamSubscription<CommentEvent>? _sub;

  RealtimeCommentsNotifier(this._ws, this._reportId) : super([]) {
    _ws.subscribeToReport(_reportId);
    _sub = _ws.commentEvents
        .where((e) => e is NewCommentEvent && e.reportId == _reportId)
        .listen((event) {
      final e = event as NewCommentEvent;
      final comment = Comment(
        id: e.id,
        reportId: e.reportId,
        deviceId: '',
        content: e.content,
        upvotes: 0,
        createdAt: e.createdAt,
        isReporter: false,
      );
      state = [comment, ...state];
    });
  }

  void seed(List<Comment> comments) {
    state = comments;
  }

  @override
  void dispose() {
    _sub?.cancel();
    _ws.unsubscribeFromReport(_reportId);
    super.dispose();
  }
}

final realtimeCommentsProvider = StateNotifierProvider.autoDispose
    .family<RealtimeCommentsNotifier, List<Comment>, String>(
  (ref, reportId) {
    final ws = ref.watch(wsServiceProvider);
    return RealtimeCommentsNotifier(ws, reportId);
  },
);
