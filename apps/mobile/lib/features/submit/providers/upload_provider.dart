import 'dart:io';

import 'package:dio/dio.dart';
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

  const UploadState({
    this.phase = UploadPhase.idle,
    this.progress = 0,
    this.errorMessage,
    this.reportId,
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
  }) {
    return UploadState(
      phase: phase ?? this.phase,
      progress: progress ?? this.progress,
      errorMessage: errorMessage,
      reportId: reportId ?? this.reportId,
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

  UploadNotifier(this._uploadService, this._reportRepository)
      : super(const UploadState());

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

      // Done
      state = state.copyWith(phase: UploadPhase.done);
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

  void cancel() {
    _cancelToken?.cancel('User cancelled upload');
    _cancelToken = null;
    state = const UploadState();
  }

  void reset() {
    _cancelToken?.cancel();
    _cancelToken = null;
    state = const UploadState();
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
