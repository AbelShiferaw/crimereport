# Milestone 27: Media Upload Integration

## Goal
Complete end-to-end report submission with media upload from Flutter app to S3 and backend.

## Dependencies
Requires **Milestone 22** (upload endpoints) and **Milestone 25** (REST integration).

## Implementation

### 1. Submit Report Flow
```dart
// lib/features/submit/presentation/report_details_screen.dart (updated)

class _ReportDetailsScreenState extends ConsumerState<ReportDetailsScreen> {
  bool _isSubmitting = false;
  double _uploadProgress = 0;
  String _uploadStatus = '';
  
  Future<void> _submitReport() async {
    if (_selectedType == null || _location == null) return;
    
    setState(() {
      _isSubmitting = true;
      _uploadStatus = 'Preparing upload...';
    });
    
    try {
      final uploadService = ref.read(uploadServiceProvider);
      final reportRepo = ref.read(reportRepositoryProvider);
      
      // 1. Upload media
      setState(() => _uploadStatus = 'Uploading media...');
      
      final uploadResult = await uploadService.uploadMedia(
        widget.mediaPath,
        onProgress: (sent, total) {
          setState(() {
            _uploadProgress = sent / total;
          });
        },
      );
      
      // 2. Create report
      setState(() {
        _uploadStatus = 'Creating report...';
        _uploadProgress = 1.0;
      });
      
      final report = await reportRepo.createReport(CreateReportRequest(
        type: _selectedType!.name,
        description: _descriptionController.text,
        latitude: _location!.latitude,
        longitude: _location!.longitude,
        address: _address,
      ));
      
      // 3. Link media to report
      setState(() => _uploadStatus = 'Processing media...');
      
      await uploadService.completeUpload(
        uploadResult.uploadId,
        report.id,
      );
      
      // 4. Success!
      _showSuccessAndNavigate();
      
    } catch (e) {
      setState(() {
        _isSubmitting = false;
        _uploadProgress = 0;
      });
      
      _showError(e.toString());
    }
  }
  
  void _showSuccessAndNavigate() {
    // Navigate back to feed
    Navigator.of(context).popUntil((route) => route.isFirst);
    
    // Show success message
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.white),
            SizedBox(width: 8),
            Text('Report submitted successfully!'),
          ],
        ),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
    
    // Refresh feed
    ref.invalidate(nearbyReportsProvider);
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // ... existing form UI ...
          
          // Upload overlay
          if (_isSubmitting)
            _buildUploadOverlay(),
        ],
      ),
    );
  }
  
  Widget _buildUploadOverlay() {
    return Container(
      color: Colors.black.withOpacity(0.8),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Progress circle
            SizedBox(
              width: 100,
              height: 100,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CircularProgressIndicator(
                    value: _uploadProgress,
                    strokeWidth: 6,
                    backgroundColor: Colors.grey[700],
                    color: Colors.red,
                  ),
                  Text(
                    '${(_uploadProgress * 100).toInt()}%',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 24),
            
            Text(
              _uploadStatus,
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
            SizedBox(height: 8),
            
            Text(
              widget.isVideo ? 'Video will be processed shortly' : '',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
```

### 2. Enhanced Upload Service
```dart
// lib/features/submit/data/services/upload_service.dart (updated)

class UploadService {
  final ApiClient _api;
  final Dio _uploadDio;
  
  UploadService(this._api) : _uploadDio = Dio();
  
  Future<UploadResult> uploadMedia(
    String filePath, {
    void Function(int sent, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final file = File(filePath);
    final filename = path.basename(filePath);
    final contentType = _getContentType(filename);
    final fileSize = await file.length();
    
    // Validate file before upload
    await _validateFile(file, contentType);
    
    // Get presigned URL
    final presigned = await _api.post<Map<String, dynamic>>(
      '/api/v1/uploads/presigned-url',
      data: {
        'filename': filename,
        'contentType': contentType,
        'fileSize': fileSize,
      },
    );
    
    // Upload to S3 with progress
    await _uploadDio.put(
      presigned['uploadUrl'],
      data: file.openRead(),
      options: Options(
        headers: {
          'Content-Type': contentType,
          'Content-Length': fileSize,
        },
      ),
      onSendProgress: onProgress,
      cancelToken: cancelToken,
    );
    
    return UploadResult(
      uploadId: presigned['uploadId'],
      key: presigned['key'],
    );
  }
  
  Future<void> _validateFile(File file, String contentType) async {
    final fileSize = await file.length();
    final isVideo = contentType.startsWith('video/');
    
    final maxSize = isVideo
        ? 100 * 1024 * 1024  // 100MB for video
        : 10 * 1024 * 1024;  // 10MB for images
    
    if (fileSize > maxSize) {
      throw UploadException(
        'File too large. Maximum size: ${maxSize ~/ (1024 * 1024)}MB'
      );
    }
    
    // Check file exists and is readable
    if (!await file.exists()) {
      throw UploadException('File not found');
    }
  }
}

class UploadException implements Exception {
  final String message;
  UploadException(this.message);
  
  @override
  String toString() => message;
}
```

### 3. Video Compression (Optional but Recommended)
```dart
// lib/features/submit/data/services/video_compressor.dart

import 'package:video_compress/video_compress.dart';

class VideoCompressor {
  Future<File?> compressVideo(String path, {
    void Function(double progress)? onProgress,
  }) async {
    final subscription = VideoCompress.compressProgress$.subscribe((progress) {
      onProgress?.call(progress);
    });
    
    try {
      final info = await VideoCompress.compressVideo(
        path,
        quality: VideoQuality.MediumQuality,
        deleteOrigin: false,
        includeAudio: true,
      );
      
      return info?.file;
    } finally {
      subscription.unsubscribe();
    }
  }
  
  Future<File?> generateThumbnail(String videoPath) async {
    final thumbnail = await VideoCompress.getFileThumbnail(
      videoPath,
      quality: 50,
      position: -1, // First frame
    );
    return thumbnail;
  }
}
```

### 4. Report Creation Request
```dart
// lib/features/submit/data/models/create_report_request.dart

class CreateReportRequest {
  final String type;
  final String description;
  final double latitude;
  final double longitude;
  final String? address;
  
  CreateReportRequest({
    required this.type,
    required this.description,
    required this.latitude,
    required this.longitude,
    this.address,
  });
  
  Map<String, dynamic> toJson() => {
    'type': type,
    'description': description,
    'latitude': latitude,
    'longitude': longitude,
    if (address != null) 'address': address,
  };
}
```

### 5. Pending Upload Status Tracker
```dart
// lib/features/submit/providers/pending_uploads_provider.dart

final pendingUploadsProvider = StateNotifierProvider<
    PendingUploadsNotifier, Map<String, PendingUpload>>((ref) {
  return PendingUploadsNotifier();
});

class PendingUpload {
  final String reportId;
  final String mediaId;
  final String status; // 'processing', 'ready', 'failed'
  final DateTime createdAt;
  
  PendingUpload({
    required this.reportId,
    required this.mediaId,
    required this.status,
    required this.createdAt,
  });
}

class PendingUploadsNotifier extends StateNotifier<Map<String, PendingUpload>> {
  PendingUploadsNotifier() : super({});
  
  void addPending(PendingUpload upload) {
    state = {...state, upload.reportId: upload};
  }
  
  void updateStatus(String reportId, String status) {
    if (state.containsKey(reportId)) {
      state = {
        ...state,
        reportId: PendingUpload(
          reportId: reportId,
          mediaId: state[reportId]!.mediaId,
          status: status,
          createdAt: state[reportId]!.createdAt,
        ),
      };
    }
  }
  
  void removePending(String reportId) {
    state = Map.from(state)..remove(reportId);
  }
}
```

### 6. Handle Media Ready WebSocket Event
```dart
// In websocket_service.dart, add to _setupListeners:

_socket!.on('media:ready', (data) {
  final reportId = data['data']['reportId'];
  final media = Media.fromJson(data['data']['media']);
  
  // Update pending uploads
  ref.read(pendingUploadsProvider.notifier).updateStatus(reportId, 'ready');
  
  // Update report in feed
  ref.read(realtimeFeedProvider.notifier).updateMedia(reportId, media);
});
```

## Upload Flow Diagram
```
User Captures Media
        │
        ▼
    [Compress?] ───(video)──> Compress Video
        │                          │
        │<─────────────────────────┘
        ▼
POST /api/reports (metadata)
  → API creates report (status: processing)
  → Returns reportId + presigned S3 URL
        │
        ▼
Upload to S3 via presigned URL (with progress)
        │
        ├─────(image)────> Step Functions: Rekognition → copy to media bucket → Ready
        │
        └─────(video)────> Step Functions: Rekognition → MediaConvert → Processing...
                               │
                               ▼
                     (Future) Step Functions updates DB + sends push
                     WebSocket: media:ready
                               │
                               ▼
                         Update UI
```

## Deliverable Checklist
- [ ] Submit flow shows upload progress
- [ ] Progress percentage accurate
- [ ] Status text updates through stages
- [ ] Video compression reduces file size
- [ ] Large files handled without crashing
- [ ] Upload cancellation works
- [ ] Error handling shows user-friendly message
- [ ] Success navigates to feed
- [ ] Feed refreshes with new report
- [ ] Video shows "processing" then updates when ready
- [ ] Multiple uploads don't conflict

## Files (6 total)
1. `lib/features/submit/presentation/report_details_screen.dart` - Update
2. `lib/features/submit/data/services/upload_service.dart` - Update
3. `lib/features/submit/data/services/video_compressor.dart` - Create
4. `lib/features/submit/data/models/create_report_request.dart` - Create
5. `lib/features/submit/providers/pending_uploads_provider.dart` - Create
6. `pubspec.yaml` - Add video_compress dependency
