import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:crimereport/core/constants/app_constants.dart';
import 'package:crimereport/shared/data/api/api_client.dart';

// ---------------------------------------------------------------------------
// Data classes
// ---------------------------------------------------------------------------

class PresignedUpload {
  final String uploadUrl;
  final String mediaKey;
  final int expiresIn;

  const PresignedUpload({
    required this.uploadUrl,
    required this.mediaKey,
    required this.expiresIn,
  });

  factory PresignedUpload.fromJson(Map<String, dynamic> json) {
    return PresignedUpload(
      uploadUrl: json['upload_url'] as String,
      mediaKey: json['media_key'] as String,
      expiresIn: json['expires_in'] as int,
    );
  }
}

class MediaPollResult {
  final String status;
  final String? mediaUrl;

  /// Optional classification of why processing failed. Set by the backend
  /// once the media pipeline error-classification work (Task 3) lands.
  /// Known values include `flagged_content`, `processing_error`, and
  /// `unsupported_format`. May be null on success or for older backends.
  final String? failureReason;

  const MediaPollResult({
    required this.status,
    this.mediaUrl,
    this.failureReason,
  });

  factory MediaPollResult.fromJson(Map<String, dynamic> json) {
    return MediaPollResult(
      status: json['status'] as String,
      mediaUrl: json['media_url'] as String?,
      failureReason: json['failure_reason'] as String?,
    );
  }

  bool get isTerminal => status == 'active' || status == 'failed';
}

class FileTooLargeException implements Exception {
  final int maxSizeMB;
  final int actualSizeMB;

  const FileTooLargeException({
    required this.maxSizeMB,
    required this.actualSizeMB,
  });

  @override
  String toString() =>
      'File too large: ${actualSizeMB}MB exceeds limit of ${maxSizeMB}MB';
}

// ---------------------------------------------------------------------------
// Upload service
// ---------------------------------------------------------------------------

class UploadService {
  final ApiClient _apiClient;
  final Dio _s3Dio;

  UploadService(this._apiClient) : _s3Dio = Dio();

  // ---- Presigned URL ----

  Future<PresignedUpload> requestUploadUrl({
    required String reportId,
    required String fileType,
    required String contentType,
  }) async {
    final response = await _apiClient.post(
      '/api/v1/reports/$reportId/upload',
      data: {
        'file_type': fileType,
        'content_type': contentType,
      },
    );
    return PresignedUpload.fromJson(response.data as Map<String, dynamic>);
  }

  // ---- S3 PUT ----

  Future<void> uploadToS3({
    required String presignedUrl,
    required File file,
    required String contentType,
    CancelToken? cancelToken,
    void Function(int, int)? onProgress,
  }) async {
    final fileLength = await file.length();
    await _s3Dio.put(
      presignedUrl,
      data: file.openRead(),
      options: Options(
        headers: {
          Headers.contentTypeHeader: contentType,
          Headers.contentLengthHeader: fileLength,
        },
      ),
      cancelToken: cancelToken,
      onSendProgress: onProgress,
    );
  }

  // ---- Confirm ----

  Future<String> confirmUpload({
    required String reportId,
    required String mediaKey,
  }) async {
    final response = await _apiClient.post(
      '/api/v1/reports/$reportId/upload/complete',
      data: {'media_key': mediaKey},
    );
    final data = response.data as Map<String, dynamic>;
    return data['status'] as String;
  }

  // ---- Poll media status ----

  Stream<MediaPollResult> pollMediaStatus(String reportId) async* {
    const pollInterval = Duration(seconds: 3);
    const maxAttempts = 60;

    for (var i = 0; i < maxAttempts; i++) {
      final response = await _apiClient.get(
        '/api/v1/reports/$reportId/media/status',
      );
      final result =
          MediaPollResult.fromJson(response.data as Map<String, dynamic>);
      yield result;

      if (result.isTerminal) return;
      await Future.delayed(pollInterval);
    }
  }

  // ---- Static helpers ----

  static String contentTypeFor(String filePath) {
    final dotIndex = filePath.lastIndexOf('.');
    final ext = dotIndex != -1 ? filePath.substring(dotIndex).toLowerCase() : '';
    return switch (ext) {
      '.jpg' || '.jpeg' => 'image/jpeg',
      '.png' => 'image/png',
      '.gif' => 'image/gif',
      '.webp' => 'image/webp',
      '.heic' || '.heif' => 'image/heic',
      '.mp4' => 'video/mp4',
      '.mov' => 'video/quicktime',
      '.avi' => 'video/x-msvideo',
      '.webm' => 'video/webm',
      _ => 'application/octet-stream',
    };
  }

  static String fileTypeFor(String contentType) {
    return contentType.startsWith('video/') ? 'video' : 'image';
  }

  static Future<void> validateFileSize(File file, String contentType) async {
    final bytes = await file.length();
    final sizeMB = (bytes / (1024 * 1024)).ceil();
    final isVideo = contentType.startsWith('video/');
    final maxMB =
        isVideo ? AppConstants.maxVideoSizeMB : AppConstants.maxImageSizeMB;

    if (sizeMB > maxMB) {
      throw FileTooLargeException(maxSizeMB: maxMB, actualSizeMB: sizeMB);
    }
  }

  void dispose() {
    _s3Dio.close();
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final uploadServiceProvider = Provider<UploadService>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  final service = UploadService(apiClient);
  ref.onDispose(() => service.dispose());
  return service;
});
