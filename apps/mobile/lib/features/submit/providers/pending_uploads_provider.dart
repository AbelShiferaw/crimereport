import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:crimereport/features/submit/data/services/upload_service.dart';

// ---------------------------------------------------------------------------
// Data class
// ---------------------------------------------------------------------------

class PendingUpload {
  final String reportId;
  final String status;
  final DateTime createdAt;

  const PendingUpload({
    required this.reportId,
    required this.status,
    required this.createdAt,
  });

  PendingUpload copyWith({String? status}) {
    return PendingUpload(
      reportId: reportId,
      status: status ?? this.status,
      createdAt: createdAt,
    );
  }
}

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

class PendingUploadsNotifier extends StateNotifier<List<PendingUpload>> {
  final UploadService _uploadService;
  final Map<String, StreamSubscription<MediaPollResult>> _subscriptions = {};

  PendingUploadsNotifier(this._uploadService) : super([]);

  void add(String reportId) {
    final upload = PendingUpload(
      reportId: reportId,
      status: 'processing',
      createdAt: DateTime.now(),
    );
    state = [...state, upload];
    _startPolling(reportId);
  }

  void _startPolling(String reportId) {
    _subscriptions[reportId]?.cancel();
    _subscriptions[reportId] =
        _uploadService.pollMediaStatus(reportId).listen(
      (result) {
        _updateStatus(reportId, result.status);
        if (result.isTerminal && result.status == 'active') {
          _scheduleRemoval(reportId);
        }
      },
      onError: (error) {
        debugPrint('Poll error for $reportId: $error');
        _updateStatus(reportId, 'error');
      },
    );
  }

  void _updateStatus(String reportId, String status) {
    state = [
      for (final upload in state)
        if (upload.reportId == reportId)
          upload.copyWith(status: status)
        else
          upload,
    ];
  }

  void _scheduleRemoval(String reportId) {
    Future.delayed(const Duration(seconds: 5), () {
      if (!mounted) return;
      _subscriptions[reportId]?.cancel();
      _subscriptions.remove(reportId);
      state = state.where((u) => u.reportId != reportId).toList();
    });
  }

  void remove(String reportId) {
    _subscriptions[reportId]?.cancel();
    _subscriptions.remove(reportId);
    state = state.where((u) => u.reportId != reportId).toList();
  }

  @override
  void dispose() {
    for (final sub in _subscriptions.values) {
      sub.cancel();
    }
    _subscriptions.clear();
    super.dispose();
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final pendingUploadsProvider =
    StateNotifierProvider<PendingUploadsNotifier, List<PendingUpload>>((ref) {
  final uploadService = ref.watch(uploadServiceProvider);
  return PendingUploadsNotifier(uploadService);
});
