import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:crimereport/features/feed/data/repositories/report_repository.dart';
import 'package:crimereport/features/submit/data/services/upload_service.dart';

// ---------------------------------------------------------------------------
// Upload phase enum
// ---------------------------------------------------------------------------

enum UploadPhase {
  idle,
  creatingReport,
  requestingUrl,
  uploading,
  confirming,
  processing,
  done,
  error;

  String get statusText => switch (this) {
        idle => '',
        creatingReport => 'Creating report…',
        requestingUrl => 'Preparing upload…',
        uploading => 'Uploading media…',
        confirming => 'Confirming upload…',
        processing => 'Processing media…',
        done => 'Report submitted!',
        error => 'Upload failed',
      };
}

// ---------------------------------------------------------------------------
// Upload state
// ---------------------------------------------------------------------------

class UploadState {
  final UploadPhase phase;
  final double progress;
  final String? errorMessage;
  final String? reportId;

  /// Non-fatal informational message surfaced alongside [phase] (e.g. a
  /// "still processing in background" notice when the polling timeout
  /// elapses but the upload itself succeeded).
  final String? infoMessage;

  const UploadState({
    this.phase = UploadPhase.idle,
    this.progress = 0,
    this.errorMessage,
    this.reportId,
    this.infoMessage,
  });

  String get statusText {
    if (phase == UploadPhase.uploading) {
      return 'Uploading… ${(progress * 100).toInt()}%';
    }
    return phase.statusText;
  }

  UploadState copyWith({
    UploadPhase? phase,
    double? progress,
    String? errorMessage,
    String? reportId,
    String? infoMessage,
  }) {
    return UploadState(
      phase: phase ?? this.phase,
      progress: progress ?? this.progress,
      errorMessage: errorMessage,
      reportId: reportId ?? this.reportId,
      infoMessage: infoMessage,
    );
  }
}

// ---------------------------------------------------------------------------
// Upload notifier
// ---------------------------------------------------------------------------

class UploadNotifier extends StateNotifier<UploadState> {
  final UploadService _uploadService;
  final ReportRepository _reportRepository;
  CancelToken? _cancelToken;
  StreamSubscription<MediaPollResult>? _pollSubscription;
  Timer? _processingTimeoutTimer;
  Completer<void>? _processingCompleter;

  UploadNotifier(this._uploadService, this._reportRepository)
      : super(const UploadState());

  /// Maps a backend `failure_reason` value to a user-facing error message.
  /// Keep this list in sync with the values the pipeline produces (see
  /// `docs/design/mobile_pipeline_followup_tasks.plan.md` Task 3).
  @visibleForTesting
  static String messageForFailureReason(String? reason) {
    switch (reason) {
      case 'flagged_content':
        return 'Your media was flagged by automatic moderation and could '
            'not be published.';
      case 'unsupported_format':
        return 'This media format is not supported. Please try a different '
            'photo or video.';
      case 'processing_error':
        return 'We had trouble processing your media. Please try again.';
      default:
        return "Your media couldn't be processed. Please try again.";
    }
  }

  Future<void> submit({
    required String filePath,
    required String type,
    required String description,
    required double lat,
    required double lng,
    String? address,
  }) async {
    if (state.phase != UploadPhase.idle &&
        state.phase != UploadPhase.error) {
      return;
    }

    _cancelToken = CancelToken();

    try {
      // Phase 1: Create report
      state = const UploadState(phase: UploadPhase.creatingReport);

      final report = await _reportRepository.createReport(
        type: type,
        description: description,
        lat: lat,
        lng: lng,
        address: address,
      );

      final reportId = report.id;
      state = state.copyWith(reportId: reportId);

      // Phase 2: Request presigned URL
      state = state.copyWith(phase: UploadPhase.requestingUrl);

      final contentType = UploadService.contentTypeFor(filePath);
      final fileType = UploadService.fileTypeFor(contentType);

      // Validate file size before uploading
      final file = File(filePath);
      await UploadService.validateFileSize(file, contentType);

      final presigned = await _uploadService.requestUploadUrl(
        reportId: reportId,
        fileType: fileType,
        contentType: contentType,
      );

      // Phase 3: Upload to S3
      state = state.copyWith(phase: UploadPhase.uploading, progress: 0);

      await _uploadService.uploadToS3(
        presignedUrl: presigned.uploadUrl,
        file: file,
        contentType: contentType,
        cancelToken: _cancelToken,
        onProgress: (sent, total) {
          if (total > 0) {
            state = state.copyWith(progress: sent / total);
          }
        },
      );

      // Phase 4: Confirm
      state = state.copyWith(phase: UploadPhase.confirming);

      await _uploadService.confirmUpload(
        reportId: reportId,
        mediaKey: presigned.mediaKey,
      );

      // Phase 5: Poll the backend until the media pipeline finishes
      // (transcoding + moderation). Until this completes the user has no
      // confirmation that their report was actually accepted.
      await waitForProcessing(reportId);
    } on FileTooLargeException catch (e) {
      state = state.copyWith(
        phase: UploadPhase.error,
        errorMessage: e.toString(),
      );
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) return;
      state = state.copyWith(
        phase: UploadPhase.error,
        errorMessage: e.message ?? 'Network error occurred',
      );
    } catch (e) {
      state = state.copyWith(
        phase: UploadPhase.error,
        errorMessage: 'Something went wrong. Please try again.',
      );
    }
  }

  /// Total time we are willing to wait for the media pipeline to reach a
  /// terminal status before falling back to a "still processing" notice.
  /// Matches the upper bound of [UploadService.pollMediaStatus] (60 polls
  /// * 3s each).
  @visibleForTesting
  static const Duration processingTimeout = Duration(minutes: 3);

  static const String _stillProcessingMessage =
      'Your report is still processing. It will appear in the feed shortly.';

  /// Subscribes to `pollMediaStatus` and resolves once the pipeline reaches
  /// a terminal status, the [processingTimeout] elapses, or the underlying
  /// stream errors / closes. Public for unit testing.
  @visibleForTesting
  Future<void> waitForProcessing(String reportId) async {
    state = state.copyWith(phase: UploadPhase.processing);

    final completer = Completer<void>();
    _processingCompleter = completer;

    void fallbackToBackground() {
      if (completer.isCompleted) return;
      _processingTimeoutTimer?.cancel();
      _processingTimeoutTimer = null;
      _pollSubscription?.cancel();
      _pollSubscription = null;
      if (mounted) {
        state = state.copyWith(
          phase: UploadPhase.done,
          infoMessage: _stillProcessingMessage,
        );
      }
      completer.complete();
    }

    _processingTimeoutTimer = Timer(processingTimeout, fallbackToBackground);

    _pollSubscription = _uploadService.pollMediaStatus(reportId).listen(
      (result) {
        if (!result.isTerminal || completer.isCompleted) return;

        _processingTimeoutTimer?.cancel();
        _processingTimeoutTimer = null;
        _pollSubscription?.cancel();
        _pollSubscription = null;

        if (mounted) {
          if (result.status == 'active') {
            state = state.copyWith(phase: UploadPhase.done);
          } else {
            state = state.copyWith(
              phase: UploadPhase.error,
              errorMessage: messageForFailureReason(result.failureReason),
            );
          }
        }
        completer.complete();
      },
      onError: (Object _) => fallbackToBackground(),
      // Stream finished without yielding a terminal status (e.g. all 60
      // polls came back as `processing`). Surface the same fallback we
      // use for the explicit timeout.
      onDone: fallbackToBackground,
      cancelOnError: true,
    );

    return completer.future;
  }

  void _cancelPolling() {
    _processingTimeoutTimer?.cancel();
    _processingTimeoutTimer = null;
    _pollSubscription?.cancel();
    _pollSubscription = null;
    final completer = _processingCompleter;
    _processingCompleter = null;
    if (completer != null && !completer.isCompleted) completer.complete();
  }

  void cancel() {
    _cancelToken?.cancel('User cancelled upload');
    _cancelToken = null;
    _cancelPolling();
    state = const UploadState();
  }

  void reset() {
    _cancelToken?.cancel();
    _cancelToken = null;
    _cancelPolling();
    state = const UploadState();
  }

  @override
  void dispose() {
    _cancelPolling();
    super.dispose();
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final uploadProvider =
    StateNotifierProvider.autoDispose<UploadNotifier, UploadState>((ref) {
  final uploadService = ref.watch(uploadServiceProvider);
  final reportRepository = ref.watch(reportRepositoryProvider);
  return UploadNotifier(uploadService, reportRepository);
});
