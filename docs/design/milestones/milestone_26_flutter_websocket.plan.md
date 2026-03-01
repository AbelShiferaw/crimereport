# Milestone 26: Flutter ↔ WebSocket

## Status
Not Started

## Goal
Add real-time updates to the Flutter app via **socket_io_client** (already in pubspec). When new reports are created nearby, upvotes change, or comments are posted, the UI updates live without manual refresh. Includes connection lifecycle management (connect, reconnect, background/foreground).

## Dependencies
- **Milestone 25** – REST API integration complete (repositories, providers, `ApiClient` in place)
- **Milestone 17** – Backend deployed with Socket.IO support on the same ECS service
- `socket_io_client: ^2.0.3+1` already in `pubspec.yaml`

## Plan

### 1. WebSocket Service

A singleton service managing the Socket.IO connection. Uses broadcast `StreamController`s so multiple providers can listen independently.

```dart
// lib/shared/data/websocket/websocket_service.dart

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:crimereport/core/constants/app_constants.dart';
import 'package:crimereport/features/settings/providers/settings_providers.dart';
import 'package:crimereport/shared/data/websocket/ws_events.dart';

enum WsConnectionState { disconnected, connecting, connected }

class WebSocketService {
  io.Socket? _socket;
  final String _baseUrl;
  String _deviceId;

  final _connectionState = ValueNotifier(WsConnectionState.disconnected);
  ValueListenable<WsConnectionState> get connectionState => _connectionState;

  final _reportEvents = StreamController<ReportEvent>.broadcast();
  final _commentEvents = StreamController<CommentEvent>.broadcast();

  Stream<ReportEvent> get reportEvents => _reportEvents.stream;
  Stream<CommentEvent> get commentEvents => _commentEvents.stream;

  WebSocketService({required String baseUrl, required String deviceId})
      : _baseUrl = baseUrl,
        _deviceId = deviceId;

  void updateDeviceId(String deviceId) => _deviceId = deviceId;

  void connect() {
    if (_socket != null) return;
    _connectionState.value = WsConnectionState.connecting;

    _socket = io.io(_baseUrl, io.OptionBuilder()
        .setTransports(['websocket'])
        .disableAutoConnect()
        .setAuth({'deviceId': _deviceId})
        .build());

    _socket!
      ..onConnect((_) {
        _connectionState.value = WsConnectionState.connected;
        debugPrint('[WS] connected');
      })
      ..onDisconnect((_) {
        _connectionState.value = WsConnectionState.disconnected;
        debugPrint('[WS] disconnected');
      })
      ..onConnectError((err) {
        _connectionState.value = WsConnectionState.disconnected;
        debugPrint('[WS] connect error: $err');
      })
      ..on('report:new', (data) {
        _reportEvents.add(NewReportEvent.fromJson(data as Map<String, dynamic>));
      })
      ..on('report:upvote', (data) {
        _reportEvents.add(UpvoteUpdateEvent.fromJson(data as Map<String, dynamic>));
      })
      ..on('comment:new', (data) {
        _commentEvents.add(NewCommentEvent.fromJson(data as Map<String, dynamic>));
      })
      ..on('media:ready', (data) {
        _reportEvents.add(MediaReadyEvent.fromJson(data as Map<String, dynamic>));
      });

    _socket!.connect();
  }

  void subscribeToLocation(double lat, double lng, {int radius = 10000}) {
    _socket?.emit('subscribe:location', {'lat': lat, 'lng': lng, 'radius': radius});
  }

  void subscribeToReport(String reportId) {
    _socket?.emit('subscribe:report', reportId);
  }

  void unsubscribeFromReport(String reportId) {
    _socket?.emit('unsubscribe:report', reportId);
  }

  void disconnect() {
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    _connectionState.value = WsConnectionState.disconnected;
  }

  void dispose() {
    disconnect();
    _reportEvents.close();
    _commentEvents.close();
    _connectionState.dispose();
  }
}

final wsServiceProvider = Provider<WebSocketService>((ref) {
  final deviceId = ref.watch(anonymousIdProvider).valueOrNull ?? '';
  final service = WebSocketService(
    baseUrl: AppConstants.wsBaseUrl,
    deviceId: deviceId,
  );
  ref.listen<AsyncValue<String>>(anonymousIdProvider, (_, next) {
    final id = next.valueOrNull;
    if (id != null) service.updateDeviceId(id);
  }, fireImmediately: true);
  ref.onDispose(() => service.dispose());
  return service;
});
```

### 2. WebSocket Event Models

Typed event classes matching the backend's Socket.IO emission payloads.

```dart
// lib/shared/data/websocket/ws_events.dart

sealed class ReportEvent {}

class NewReportEvent extends ReportEvent {
  final String id;
  final String type;
  final double lat;
  final double lng;
  final String? address;
  final String? thumbnailUrl;
  final DateTime createdAt;

  NewReportEvent({
    required this.id,
    required this.type,
    required this.lat,
    required this.lng,
    this.address,
    this.thumbnailUrl,
    required this.createdAt,
  });

  factory NewReportEvent.fromJson(Map<String, dynamic> json) => NewReportEvent(
        id: json['id'] as String,
        type: json['type'] as String,
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
        address: json['address'] as String?,
        thumbnailUrl: json['thumbnail_url'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}

class UpvoteUpdateEvent extends ReportEvent {
  final String reportId;
  final int upvotes;

  UpvoteUpdateEvent({required this.reportId, required this.upvotes});

  factory UpvoteUpdateEvent.fromJson(Map<String, dynamic> json) => UpvoteUpdateEvent(
        reportId: json['report_id'] as String,
        upvotes: json['upvotes'] as int,
      );
}

class MediaReadyEvent extends ReportEvent {
  final String reportId;
  final String mediaUrl;
  final String? thumbnailUrl;

  MediaReadyEvent({required this.reportId, required this.mediaUrl, this.thumbnailUrl});

  factory MediaReadyEvent.fromJson(Map<String, dynamic> json) => MediaReadyEvent(
        reportId: json['report_id'] as String,
        mediaUrl: json['media_url'] as String,
        thumbnailUrl: json['thumbnail_url'] as String?,
      );
}

class CommentEvent {}

class NewCommentEvent extends CommentEvent {
  final String id;
  final String reportId;
  final String content;
  final String deviceId;
  final bool isReporter;
  final DateTime createdAt;

  NewCommentEvent({
    required this.id,
    required this.reportId,
    required this.content,
    required this.deviceId,
    required this.isReporter,
    required this.createdAt,
  });

  factory NewCommentEvent.fromJson(Map<String, dynamic> json) => NewCommentEvent(
        id: json['id'] as String,
        reportId: json['report_id'] as String,
        content: json['content'] as String,
        deviceId: json['device_id'] as String,
        isReporter: json['is_reporter'] as bool? ?? false,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}
```

### 3. Real-Time Feed Provider

A `StateNotifier` that holds the current feed and applies real-time patches on top of the initial REST fetch. The feed screen seeds it once from `feedReportsProvider` (Milestone 25), then WebSocket events mutate state in-place.

```dart
// lib/features/feed/providers/realtime_feed_provider.dart

import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:crimereport/features/feed/data/models/report.dart';
import 'package:crimereport/core/constants/enums.dart';
import 'package:crimereport/shared/data/websocket/websocket_service.dart';
import 'package:crimereport/shared/data/websocket/ws_events.dart';

class RealtimeFeedNotifier extends StateNotifier<List<Report>> {
  final List<StreamSubscription> _subs = [];

  RealtimeFeedNotifier(WebSocketService ws) : super([]) {
    _subs.add(ws.reportEvents.listen(_handleReportEvent));
  }

  void seed(List<Report> reports) => state = reports;

  void _handleReportEvent(ReportEvent event) {
    switch (event) {
      case NewReportEvent e:
        final report = Report(
          id: e.id,
          deviceId: '',
          type: ReportType.values.byName(e.type),
          description: '',
          latitude: e.lat,
          longitude: e.lng,
          address: e.address,
          media: [],
          upvotes: 0,
          commentCount: 0,
          createdAt: e.createdAt,
          status: ReportStatus.pending,
        );
        state = [report, ...state];

      case UpvoteUpdateEvent e:
        state = [
          for (final r in state)
            if (r.id == e.reportId) r.copyWith(upvotes: e.upvotes) else r,
        ];

      case MediaReadyEvent e:
        // Trigger a refetch for this report so full media data loads
        // (handled in the feed screen by invalidating the single-report provider)
        break;
    }
  }

  @override
  void dispose() {
    for (final sub in _subs) {
      sub.cancel();
    }
    super.dispose();
  }
}

final realtimeFeedProvider =
    StateNotifierProvider<RealtimeFeedNotifier, List<Report>>((ref) {
  final ws = ref.watch(wsServiceProvider);
  return RealtimeFeedNotifier(ws);
});
```

### 4. Real-Time Comments Provider

Per-report comment stream. Subscribes to the report's room on mount, unsubscribes on dispose.

```dart
// lib/features/feed/providers/realtime_comments_provider.dart

import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:crimereport/features/feed/data/models/comment.dart';
import 'package:crimereport/shared/data/websocket/websocket_service.dart';
import 'package:crimereport/shared/data/websocket/ws_events.dart';

class RealtimeCommentsNotifier extends StateNotifier<List<Comment>> {
  final WebSocketService _ws;
  final String _reportId;
  StreamSubscription? _sub;

  RealtimeCommentsNotifier(this._ws, this._reportId) : super([]) {
    _ws.subscribeToReport(_reportId);
    _sub = _ws.commentEvents
        .where((e) => e is NewCommentEvent && e.reportId == _reportId)
        .cast<NewCommentEvent>()
        .listen((e) {
      state = [
        Comment(
          id: e.id,
          reportId: e.reportId,
          deviceId: e.deviceId,
          content: e.content,
          upvotes: 0,
          createdAt: e.createdAt,
          isReporter: e.isReporter,
        ),
        ...state,
      ];
    });
  }

  void seed(List<Comment> comments) => state = comments;

  @override
  void dispose() {
    _sub?.cancel();
    _ws.unsubscribeFromReport(_reportId);
    super.dispose();
  }
}

final realtimeCommentsProvider = StateNotifierProvider.autoDispose
    .family<RealtimeCommentsNotifier, List<Comment>, String>((ref, reportId) {
  final ws = ref.watch(wsServiceProvider);
  return RealtimeCommentsNotifier(ws, reportId);
});
```

### 5. Connection Lifecycle Manager

Connects on app foreground, disconnects on background. Subscribes to user location so the server knows which area to broadcast for.

```dart
// lib/shared/data/websocket/ws_lifecycle_manager.dart

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:crimereport/shared/data/websocket/websocket_service.dart';
import 'package:crimereport/features/map/providers/map_providers.dart';

class WsLifecycleManager extends WidgetsBindingObserver {
  final WebSocketService _ws;
  final Ref _ref;

  WsLifecycleManager(this._ws, this._ref) {
    WidgetsBinding.instance.addObserver(this);
    _connect();
  }

  void _connect() {
    _ws.connect();
    final position = _ref.read(userLocationProvider);
    if (position != null) {
      _ws.subscribeToLocation(position.latitude, position.longitude);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _connect();
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _ws.disconnect();
      default:
        break;
    }
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
  }
}

final wsLifecycleProvider = Provider<WsLifecycleManager>((ref) {
  final ws = ref.watch(wsServiceProvider);
  final manager = WsLifecycleManager(ws, ref);
  ref.onDispose(() => manager.dispose());
  return manager;
});
```

### 6. Wire Up in AppShell

Initialize the WebSocket lifecycle early — read the provider in `AppShell` so it stays alive for the app's lifetime.

```dart
// lib/shared/widgets/app_shell.dart  (add to build method)

// Somewhere near the top of build():
ref.watch(wsLifecycleProvider);
```

### 7. New Report Banner Widget

Overlay banner shown when a `NewReportEvent` arrives while the user is mid-scroll. Tapping scrolls to the top.

```dart
// lib/features/feed/presentation/widgets/new_report_banner.dart

import 'package:flutter/material.dart';

class NewReportBanner extends StatelessWidget {
  final VoidCallback onTap;
  const NewReportBanner({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.redAccent,
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 8, offset: Offset(0, 2))],
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.arrow_upward_rounded, color: Colors.white, size: 16),
            SizedBox(width: 4),
            Text('New Report Nearby', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}
```

## Testing Plan

- **Unit tests** for `WebSocketService` — mock `io.Socket`, verify `connect()` / `disconnect()` state transitions, verify event parsing from raw JSON to typed events.
- **Unit tests** for `RealtimeFeedNotifier` — seed with reports, push `NewReportEvent` → verify prepend, push `UpvoteUpdateEvent` → verify in-place update.
- **Unit tests** for `RealtimeCommentsNotifier` — verify comments stream filtered by reportId.
- **Unit tests** for `WsLifecycleManager` — verify `didChangeAppLifecycleState` calls connect/disconnect.
- **Widget test** for `NewReportBanner` — verify tap callback fires.
- **Integration test** — connect to a local Socket.IO server, emit `report:new`, verify feed updates.

## Notes

- **No new dependencies** — `socket_io_client: ^2.0.3+1` is already in pubspec.
- **Event field names use snake_case** to match the backend's JSON convention (`report_id`, `created_at`, `thumbnail_url`). The event `fromJson` factories follow the same pattern as existing `Report.fromJson` / `Comment.fromJson`.
- **Sealed classes** — `ReportEvent` uses a sealed class with exhaustive switch in the notifier, requiring Dart 3.0+ (SDK `^3.10.8` in pubspec satisfies this).
- **Reconnection** is handled by Socket.IO's built-in reconnect logic. `WsLifecycleManager` handles the app-level foreground/background transitions.
- **Location subscription** — the initial location-based subscription uses the position from `userLocationProvider`. When the user moves significantly (Geolocator stream), re-subscribe with the new coordinates.
- **Map markers** — the map screen should also listen to `realtimeFeedProvider` so new reports appear as markers without a manual refresh.

## Files

| # | Path | Action |
|---|------|--------|
| 1 | `lib/shared/data/websocket/websocket_service.dart` | Create |
| 2 | `lib/shared/data/websocket/ws_events.dart` | Create |
| 3 | `lib/shared/data/websocket/ws_lifecycle_manager.dart` | Create |
| 4 | `lib/features/feed/providers/realtime_feed_provider.dart` | Create |
| 5 | `lib/features/feed/providers/realtime_comments_provider.dart` | Create |
| 6 | `lib/features/feed/presentation/widgets/new_report_banner.dart` | Create |
| 7 | `lib/shared/widgets/app_shell.dart` | Modify — watch `wsLifecycleProvider` |
| 8 | `lib/features/feed/presentation/feed_screen.dart` | Modify — seed realtimeFeedProvider, show banner |
| 9 | `lib/features/feed/presentation/widgets/comments_sheet.dart` | Modify — seed realtimeCommentsProvider |
