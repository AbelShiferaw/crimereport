import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:crimereport/core/constants/app_constants.dart';
import 'package:crimereport/features/map/providers/map_providers.dart';
import 'package:crimereport/shared/data/websocket/websocket_service.dart';

class WsLifecycleManager extends WidgetsBindingObserver {
  final Ref _ref;
  bool _attached = false;

  WsLifecycleManager(this._ref) {
    _attach();
    _connectAndSubscribe();
  }

  void _attach() {
    if (!_attached) {
      WidgetsBinding.instance.addObserver(this);
      _attached = true;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final ws = _ref.read(wsServiceProvider);
    switch (state) {
      case AppLifecycleState.resumed:
        _connectAndSubscribe();
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        ws.disconnect();
      default:
        break;
    }
  }

  void _connectAndSubscribe() {
    final ws = _ref.read(wsServiceProvider);
    if (ws.currentState == WsConnectionState.disconnected) {
      ws.connect();
    }

    final position = _ref.read(userLocationProvider);
    if (position != null) {
      ws.subscribeToLocation(
        position.latitude,
        position.longitude,
        radius: AppConstants.defaultRadiusMeters.toDouble(),
      );
    }
  }

  void dispose() {
    if (_attached) {
      WidgetsBinding.instance.removeObserver(this);
      _attached = false;
    }
  }
}

final wsLifecycleProvider = Provider<WsLifecycleManager>((ref) {
  final manager = WsLifecycleManager(ref);
  ref.onDispose(() => manager.dispose());
  return manager;
});
