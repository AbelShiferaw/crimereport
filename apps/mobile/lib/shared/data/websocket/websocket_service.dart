import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:socket_io_client/socket_io_client.dart' as sio;

import 'package:crimereport/core/constants/app_constants.dart';
import 'package:crimereport/features/settings/providers/settings_providers.dart';
import 'package:crimereport/shared/data/websocket/ws_events.dart';

enum WsConnectionState { disconnected, connecting, connected }

class WebSocketService {
  final String _url;
  final String _deviceId;

  sio.Socket? _socket;
  WsConnectionState _state = WsConnectionState.disconnected;

  final _reportEvents = StreamController<ReportEvent>.broadcast();
  final _commentEvents = StreamController<CommentEvent>.broadcast();
  final _connectionState = StreamController<WsConnectionState>.broadcast();

  Stream<ReportEvent> get reportEvents => _reportEvents.stream;
  Stream<CommentEvent> get commentEvents => _commentEvents.stream;
  Stream<WsConnectionState> get connectionState => _connectionState.stream;
  WsConnectionState get currentState => _state;

  WebSocketService({required String url, required String deviceId})
      : _url = url,
        _deviceId = deviceId;

  void _setState(WsConnectionState state) {
    _state = state;
    _connectionState.add(state);
  }

  void connect() {
    if (_state != WsConnectionState.disconnected) return;
    _setState(WsConnectionState.connecting);

    _socket = sio.io(
      _url,
      sio.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'deviceId': _deviceId})
          .disableAutoConnect()
          .build(),
    );

    _socket!.onConnect((_) {
      debugPrint('[WS] connected');
      _setState(WsConnectionState.connected);
    });

    _socket!.onDisconnect((_) {
      debugPrint('[WS] disconnected');
      _setState(WsConnectionState.disconnected);
    });

    _socket!.onConnectError((err) {
      debugPrint('[WS] connect error: $err');
      _setState(WsConnectionState.disconnected);
    });

    _socket!.on('report:new', (data) {
      try {
        final event = NewReportEvent.fromJson(
          Map<String, dynamic>.from(data as Map),
        );
        _reportEvents.add(event);
      } catch (e) {
        debugPrint('[WS] failed to parse report:new: $e');
      }
    });

    _socket!.on('report:upvote', (data) {
      try {
        final event = UpvoteUpdateEvent.fromJson(
          Map<String, dynamic>.from(data as Map),
        );
        _reportEvents.add(event);
      } catch (e) {
        debugPrint('[WS] failed to parse report:upvote: $e');
      }
    });

    _socket!.on('media:ready', (data) {
      try {
        final event = MediaReadyEvent.fromJson(
          Map<String, dynamic>.from(data as Map),
        );
        _reportEvents.add(event);
      } catch (e) {
        debugPrint('[WS] failed to parse media:ready: $e');
      }
    });

    _socket!.on('comment:new', (data) {
      try {
        final event = NewCommentEvent.fromJson(
          Map<String, dynamic>.from(data as Map),
        );
        _commentEvents.add(event);
      } catch (e) {
        debugPrint('[WS] failed to parse comment:new: $e');
      }
    });

    _socket!.connect();
  }

  void disconnect() {
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    _setState(WsConnectionState.disconnected);
  }

  void subscribeToLocation(double lat, double lng, {double? radius}) {
    _socket?.emit('subscribe:location', {
      'lat': lat,
      'lng': lng,
      if (radius != null) 'radius': radius,
    });
  }

  void unsubscribeFromLocation() {
    _socket?.emit('unsubscribe:location');
  }

  void subscribeToReport(String reportId) {
    _socket?.emit('subscribe:report', reportId);
  }

  void unsubscribeFromReport(String reportId) {
    _socket?.emit('unsubscribe:report', reportId);
  }

  void dispose() {
    disconnect();
    _reportEvents.close();
    _commentEvents.close();
    _connectionState.close();
  }
}

final wsServiceProvider = Provider<WebSocketService>((ref) {
  final asyncId = ref.watch(anonymousIdProvider);
  final deviceId = asyncId.valueOrNull ?? '';

  final service = WebSocketService(
    url: AppConstants.wsBaseUrl,
    deviceId: deviceId,
  );

  ref.onDispose(() => service.dispose());
  return service;
});
