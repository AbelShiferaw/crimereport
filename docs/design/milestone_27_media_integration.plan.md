# Milestone 27: Media Upload Integration

## Status
Not Started

## Goal
Connect the existing camera/gallery capture flow (`CameraScreen` → `MediaPreviewScreen` → `ReportDetailsScreen`) to the backend's two-phase upload pipeline: (1) request a presigned S3 URL, (2) PUT the file directly to S3, (3) confirm upload completion, (4) poll for processing status. Uses **dio** for the S3 PUT with progress tracking.

## Dependencies
- **Milestone 25** – `ApiClient` and `ReportRepository` in place
- **Milestone 16** – S3 buckets, CloudFront, and Lambda/Step Functions media pipeline deployed
- **Milestone 15** – `media` table in database
- Backend endpoints already implemented in `backend/api/src/routes/reports.ts`:
  - `POST /api/v1/reports/:id/upload` — returns presigned URL
  - `POST /api/v1/reports/:id/upload/complete` — confirms upload
  - `GET /api/v1/reports/:id/media/status` — polls processing status

## Plan

### 1. Upload Service

Orchestrates the two-phase upload. Uses a separate `Dio` instance for the raw S3 PUT (no auth headers, just the presigned URL). Supports progress callbacks and cancellation.

```dart
// lib/features/submit/data/services/upload_service.dart

import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:crimereport/shared/data/api/api_client.dart';
import 'package:crimereport/core/constants/app_constants.dart';

class UploadService {
  final ApiClient _api;
  final Dio _s3Dio = Dio();

  UploadService(this._api);

  /// Phase 1: Request a presigned upload URL from the backend.
  /// Returns { upload_url, media_key, expires_in }.
  Future<PresignedUpload> requestUploadUrl({
    required String reportId,
    required String fileType,
    required String contentType,
  }) async {
    final response = await _api.dio.post(
      '/api/v1/reports/$reportId/upload',
      data: {
        'device_id': _api.dio.options.headers['X-Device-ID'],
        'file_type': fileType,
        'content_type': contentType,
      },
    );
    return PresignedUpload.fromJson(response.data as Map<String, dynamic>);
  }

  /// Phase 2: Upload the file directly to S3 via the presigned URL.
  Future<void> uploadToS3({
    required String presignedUrl,
    required File file,
    required String contentType,
    CancelToken? cancelToken,
    void Function(int sent, int total)? onProgress,
  }) async {
    final fileLength = await file.length();
    await _s3Dio.put(
      presignedUrl,
      data: file.openRead(),
      options: Options(
        headers: {
          HttpHeaders.contentTypeHeader: contentType,
          HttpHeaders.contentLengthHeader: fileLength,
        },
      ),
      cancelToken: cancelToken,
      onSendProgress: onProgress,
    );
  }

  /// Phase 3: Notify the backend that the S3 upload finished.
  /// Returns the initial processing status (usually 'processing').
  Future<String> confirmUpload({
    required String reportId,
    required String mediaKey,
  }) async {
    final response = await _api.dio.post(
      '/api/v1/reports/$reportId/upload/complete',
      data: {
        'device_id': _api.dio.options.headers['X-Device-ID'],
        'media_key': mediaKey,
      },
    );
    return response.data['status'] as String;
  }

  /// Phase 4: Poll the media processing status until 'active' or 'failed'.
  /// Yields status strings so the UI can update.
  Stream<MediaPollResult> pollMediaStatus(String reportId) async* {
    const pollInterval = Duration(seconds: 3);
    const maxAttempts = 60; // 3 minutes max

    for (var i = 0; i < maxAttempts; i++) {
      await Future.delayed(pollInterval);
      final response = await _api.dio.get('/api/v1/reports/$reportId/media/status');
      final status = response.data['status'] as String;
      final media = response.data['media'] as List<dynamic>;

      yield MediaPollResult(status: status, mediaItems: media);

      if (status == 'active' || status == 'failed') break;
    }
  }

  /// Determine content type from file extension.
  static String contentTypeFor(String filePath) {
    final ext = p.extension(filePath).toLowerCase();
    return switch (ext) {
      '.jpg' || '.jpeg' => 'image/jpeg',
      '.png' => 'image/png',
      '.webp' => 'image/webp',
      '.mp4' => 'video/mp4',
      '.mov' => 'video/quicktime',
      '.webm' => 'video/webm',
      _ => throw UnsupportedError('Unsupported file type: $ext'),
    };
  }

  /// Determine file_type ('image' or 'video') from content type.
  static String fileTypeFor(String contentType) {
    return contentType.startsWith('video/') ? 'video' : 'image';
  }

  /// Validate file size before uploading.
  static Future<void> validateFileSize(File file, String contentType) async {
    final bytes = await file.length();
    final isVideo = contentType.startsWith('video/');
    final maxBytes = isVideo
        ? AppConstants.maxVideoSizeMB * 1024 * 1024
        : AppConstants.maxImageSizeMB * 1024 * 1024;

    if (bytes > maxBytes) {
      final maxMB = isVideo ? AppConstants.maxVideoSizeMB : AppConstants.maxImageSizeMB;
      throw FileTooLargeException('File exceeds ${maxMB}MB limit');
    }
  }
}

class PresignedUpload {
  final String uploadUrl;
  final String mediaKey;
  final int expiresIn;

  PresignedUpload({required this.uploadUrl, required this.mediaKey, required this.expiresIn});

  factory PresignedUpload.fromJson(Map<String, dynamic> json) => PresignedUpload(
        uploadUrl: json['upload_url'] as String,
        mediaKey: json['media_key'] as String,
        expiresIn: json['expires_in'] as int,
      );
}

class MediaPollResult {
  final String status;
  final List<dynamic> mediaItems;
  MediaPollResult({required this.status, required this.mediaItems});
}

class FileTooLargeException implements Exception {
  final String message;
  FileTooLargeException(this.message);
  @override
  String toString() => message;
}

final uploadServiceProvider = Provider<UploadService>((ref) {
  return UploadService(ref.watch(apiClientProvider));
});
```

### 2. Upload State Notifier

Manages the full submit-and-upload lifecycle as a state machine. The `ReportDetailsScreen` watches this provider to drive the overlay UI.

```dart
// lib/features/submit/providers/upload_provider.dart

import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:crimereport/features/feed/data/repositories/report_repository.dart';
import 'package:crimereport/features/submit/data/services/upload_service.dart';

enum UploadPhase { idle, creatingReport, requestingUrl, uploading, confirming, processing, done, error }

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

  UploadState copyWith({UploadPhase? phase, double? progress, String? errorMessage, String? reportId}) =>
      UploadState(
        phase: phase ?? this.phase,
        progress: progress ?? this.progress,
        errorMessage: errorMessage ?? this.errorMessage,
        reportId: reportId ?? this.reportId,
      );

  String get statusText => switch (phase) {
        UploadPhase.idle => '',
        UploadPhase.creatingReport => 'Creating report...',
        UploadPhase.requestingUrl => 'Preparing upload...',
        UploadPhase.uploading => 'Uploading media... ${(progress * 100).toInt()}%',
        UploadPhase.confirming => 'Confirming upload...',
        UploadPhase.processing => 'Processing media...',
        UploadPhase.done => 'Done!',
        UploadPhase.error => errorMessage ?? 'Upload failed',
      };
}

class UploadNotifier extends StateNotifier<UploadState> {
  final ReportRepository _reportRepo;
  final UploadService _uploadService;
  CancelToken? _cancelToken;

  UploadNotifier(this._reportRepo, this._uploadService) : super(const UploadState());

  Future<void> submit({
    required String filePath,
    required String type,
    required String description,
    required double lat,
    required double lng,
    String? address,
  }) async {
    _cancelToken = CancelToken();

    try {
      // 1. Create the report
      state = state.copyWith(phase: UploadPhase.creatingReport);
      final report = await _reportRepo.createReport(
        type: type,
        description: description,
        lat: lat,
        lng: lng,
        address: address,
      );
      state = state.copyWith(reportId: report.id);

      // 2. Request presigned URL
      state = state.copyWith(phase: UploadPhase.requestingUrl);
      final contentType = UploadService.contentTypeFor(filePath);
      final fileType = UploadService.fileTypeFor(contentType);
      final file = File(filePath);

      await UploadService.validateFileSize(file, contentType);

      final presigned = await _uploadService.requestUploadUrl(
        reportId: report.id,
        fileType: fileType,
        contentType: contentType,
      );

      // 3. Upload to S3
      state = state.copyWith(phase: UploadPhase.uploading, progress: 0);
      await _uploadService.uploadToS3(
        presignedUrl: presigned.uploadUrl,
        file: file,
        contentType: contentType,
        cancelToken: _cancelToken,
        onProgress: (sent, total) {
          if (total > 0) state = state.copyWith(progress: sent / total);
        },
      );

      // 4. Confirm upload
      state = state.copyWith(phase: UploadPhase.confirming, progress: 1.0);
      await _uploadService.confirmUpload(
        reportId: report.id,
        mediaKey: presigned.mediaKey,
      );

      // 5. Done — processing happens server-side asynchronously
      state = state.copyWith(phase: UploadPhase.done);

    } on FileTooLargeException catch (e) {
      state = state.copyWith(phase: UploadPhase.error, errorMessage: e.message);
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) return;
      state = state.copyWith(phase: UploadPhase.error, errorMessage: 'Upload failed. Please try again.');
    } catch (e) {
      state = state.copyWith(phase: UploadPhase.error, errorMessage: e.toString());
    }
  }

  void cancel() {
    _cancelToken?.cancel();
    state = const UploadState();
  }

  void reset() => state = const UploadState();
}

final uploadProvider = StateNotifierProvider.autoDispose<UploadNotifier, UploadState>((ref) {
  return UploadNotifier(
    ref.watch(reportRepositoryProvider),
    ref.watch(uploadServiceProvider),
  );
});
```

### 3. Update ReportDetailsScreen

Replace the mock `_submit()` with the real upload flow. The screen watches `uploadProvider` to drive the overlay state.

```dart
// lib/features/submit/presentation/report_details_screen.dart  (key changes)

// Convert to ConsumerStatefulWidget, add WidgetRef access.
// Replace the existing _submit() method:

Future<void> _submit() async {
  if (!_isFormValid || _isSubmitting) return;
  _descriptionFocus.unfocus();

  ref.read(uploadProvider.notifier).submit(
    filePath: widget.filePath,
    type: _selectedType!.name,
    description: _descriptionController.text.trim(),
    lat: _location!.latitude,
    lng: _location!.longitude,
  );
}

// In build(), wrap with a listener that navigates on success:
ref.listen<UploadState>(uploadProvider, (_, state) {
  if (state.phase == UploadPhase.done) {
    Navigator.of(context).popUntil((route) => route.isFirst);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Report submitted! Media is processing.'),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
    ref.invalidate(feedReportsProvider);
  }
});

// Show the upload overlay when phase != idle:
final uploadState = ref.watch(uploadProvider);
if (uploadState.phase != UploadPhase.idle) _buildUploadOverlay(uploadState),
```

### 4. Upload Overlay Widget

A full-screen overlay showing phase progress, percentage, and a cancel button.

```dart
// lib/features/submit/presentation/widgets/upload_overlay.dart

import 'package:flutter/material.dart';
import 'package:crimereport/core/theme/theme.dart';
import 'package:crimereport/features/submit/providers/upload_provider.dart';

class UploadOverlay extends StatelessWidget {
  final UploadState state;
  final VoidCallback onCancel;

  const UploadOverlay({super.key, required this.state, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withAlpha(200),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 100,
              height: 100,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CircularProgressIndicator(
                    value: state.phase == UploadPhase.uploading ? state.progress : null,
                    strokeWidth: 6,
                    backgroundColor: Colors.grey[800],
                    color: state.phase == UploadPhase.error ? Colors.red : AppColors.primary,
                  ),
                  if (state.phase == UploadPhase.uploading)
                    Text(
                      '${(state.progress * 100).toInt()}%',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                  if (state.phase == UploadPhase.error)
                    const Icon(Icons.error_outline, color: Colors.red, size: 36),
                  if (state.phase == UploadPhase.done)
                    const Icon(Icons.check_circle, color: Colors.green, size: 36),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text(state.statusText, style: const TextStyle(color: Colors.white, fontSize: 16)),
            const SizedBox(height: 16),
            if (state.phase == UploadPhase.uploading)
              TextButton(onPressed: onCancel, child: const Text('Cancel', style: TextStyle(color: Colors.grey))),
            if (state.phase == UploadPhase.error)
              TextButton(onPressed: onCancel, child: const Text('Dismiss', style: TextStyle(color: Colors.grey))),
          ],
        ),
      ),
    );
  }
}
```

### 5. Pending Upload Tracker (optional background polling)

For reports where the user navigated away before processing finished, track pending uploads and poll in the background. Useful for video reports that take longer to transcode.

```dart
// lib/features/submit/providers/pending_uploads_provider.dart

import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:crimereport/features/submit/data/services/upload_service.dart';

class PendingUpload {
  final String reportId;
  final String status;
  final DateTime createdAt;
  PendingUpload({required this.reportId, required this.status, required this.createdAt});
}

class PendingUploadsNotifier extends StateNotifier<Map<String, PendingUpload>> {
  final UploadService _uploadService;
  final Map<String, StreamSubscription> _pollers = {};

  PendingUploadsNotifier(this._uploadService) : super({});

  void track(String reportId) {
    state = {
      ...state,
      reportId: PendingUpload(reportId: reportId, status: 'processing', createdAt: DateTime.now()),
    };
    _startPolling(reportId);
  }

  void _startPolling(String reportId) {
    _pollers[reportId]?.cancel();
    _pollers[reportId] = _uploadService.pollMediaStatus(reportId).listen((result) {
      state = {
        ...state,
        reportId: PendingUpload(reportId: reportId, status: result.status, createdAt: state[reportId]!.createdAt),
      };
      if (result.status == 'active' || result.status == 'failed') {
        _pollers[reportId]?.cancel();
        _pollers.remove(reportId);
        // Auto-remove successful uploads after a delay
        if (result.status == 'active') {
          Future.delayed(const Duration(seconds: 5), () {
            if (mounted) {
              state = Map.from(state)..remove(reportId);
            }
          });
        }
      }
    });
  }

  @override
  void dispose() {
    for (final sub in _pollers.values) {
      sub.cancel();
    }
    super.dispose();
  }
}

final pendingUploadsProvider =
    StateNotifierProvider<PendingUploadsNotifier, Map<String, PendingUpload>>((ref) {
  return PendingUploadsNotifier(ref.watch(uploadServiceProvider));
});
```

## Testing Plan

- **Unit tests** for `UploadService` — mock dio, verify correct URL/body for `requestUploadUrl`, `confirmUpload`, and `pollMediaStatus`. Verify `contentTypeFor` mapping.
- **Unit tests** for `UploadNotifier` — walk through the state machine: idle → creatingReport → requestingUrl → uploading → confirming → done. Verify error states. Verify cancel resets state.
- **Unit tests** for `validateFileSize` — verify it throws `FileTooLargeException` for oversized files.
- **Widget tests** for `UploadOverlay` — verify progress percentage display, cancel button visibility per phase.
- **Integration test** — capture media via camera, fill form, submit, verify presigned URL request, S3 PUT, confirm call, and navigation back to feed.

## Notes

- **Two-phase upload flow:** The backend creates the report first (POST `/reports`), then the client requests an upload URL (POST `/reports/:id/upload`), uploads to S3, and confirms (POST `/reports/:id/upload/complete`). This matches the existing backend exactly — see `reports.ts` lines 150-238.
- **Report status lifecycle:** `pending` → `uploading` → `processing` → `active` (or `failed`). The backend sets `uploading` on presigned URL request and `processing` on confirm. The Step Functions pipeline moves to `active` when done.
- **`ReportDetailsScreen` becomes `ConsumerStatefulWidget`** — currently a plain `StatefulWidget`. Needs `WidgetRef` to read providers.
- **No new dependencies** — uses `dio` (already present) for S3 PUT. The `path` package is available via Flutter SDK.
- **Video compression** is deferred — can be added later with `video_compress` if needed. The backend's MediaConvert pipeline handles transcoding.
- **The `media:ready` WebSocket event** (Milestone 26) will also fire when processing completes, which can be used to update the feed in addition to polling.
- **File size limits** reference `AppConstants.maxVideoSizeMB` (100) and `AppConstants.maxImageSizeMB` (10), already defined.

## Files

| # | Path | Action |
|---|------|--------|
| 1 | `lib/features/submit/data/services/upload_service.dart` | Create |
| 2 | `lib/features/submit/providers/upload_provider.dart` | Create |
| 3 | `lib/features/submit/providers/pending_uploads_provider.dart` | Create |
| 4 | `lib/features/submit/presentation/widgets/upload_overlay.dart` | Create |
| 5 | `lib/features/submit/presentation/report_details_screen.dart` | Modify — convert to ConsumerStatefulWidget, wire up uploadProvider |
| 6 | `lib/features/submit/presentation/media_preview_screen.dart` | Modify — pass through to updated ReportDetailsScreen |
