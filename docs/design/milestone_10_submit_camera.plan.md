# Milestone 10: Submit Report - Camera

## Status
Completed

## Goal
Build the full camera capture flow for crime report evidence: camera screen with photo/video mode, flash/zoom/flip controls, recording timer with max duration, lifecycle-aware controller management, and a media preview screen with retake/confirm actions. Also includes the submit entry screen with gallery upload support.

## Dependencies
Requires **Milestone 1** complete (project structure with `camera`, `video_player`, `image_picker`, and `permission_handler` packages).

## What Was Built
- Full-screen camera with photo/video toggle, pinch-to-zoom + slider zoom, flash (off/auto/on cycle), front/back camera flip
- Recording timer with configurable max duration (300s) and auto-stop
- Lifecycle-aware controller disposal and recording recovery (saves in-progress recording when app backgrounds)
- Back-navigation guard that finishes recording before popping
- Media preview screen with video playback (looping, play/pause), retake/confirm actions, and gallery-sourced media support
- Submit entry screen (`SubmitScreen`) with permission handling (request, denied, permanently denied → settings dialog), camera launch, gallery picker with media type sheet, and navigation to `ReportDetailsScreen`

## Key Files
| File | Description |
|------|-------------|
| `apps/mobile/lib/features/submit/presentation/camera_screen.dart` | Full-screen camera with all controls and lifecycle handling |
| `apps/mobile/lib/features/submit/presentation/camera_controls.dart` | Reusable widgets: `CaptureMode` enum, `CameraCircleButton`, `CameraModeTab`, `CameraCaptureButton` |
| `apps/mobile/lib/features/submit/presentation/media_preview_screen.dart` | Photo/video preview with retake and confirm actions |
| `apps/mobile/lib/features/submit/presentation/submit_screen.dart` | Entry screen with "Open Camera" / "Upload from Gallery" buttons and permission flows |
| `apps/mobile/lib/core/constants/app_constants.dart` | `maxRecordingDurationSeconds`, `standardTransition`, and other constants used here |

## Implementation Details

### 1. Camera Screen — State and Lifecycle

`CameraScreen` is a `StatefulWidget` that mixes in `WidgetsBindingObserver` for lifecycle handling. It manages camera initialization, mode switching, recording state, zoom, and flash.

```dart
class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  int _currentCameraIndex = 0;
  bool _isInitializing = true;
  String? _errorMessage;

  CaptureMode _mode = CaptureMode.video;
  bool _isRecording = false;
  bool _isTakingPhoto = false;
  bool _isSwitchingCamera = false;
  FlashMode _flashMode = FlashMode.off;

  Timer? _recordingTimer;
  int _recordingSeconds = 0;
  static const int _maxRecordingSeconds = AppConstants.maxRecordingDurationSeconds;

  String? _pendingPreviewPath;

  double _minZoom = 1.0;
  double _maxZoom = 1.0;
  double _currentZoom = 1.0;
  double _pinchZoomStart = 1.0;
}
```

When the app goes to `inactive` state during recording, `_finishRecordingAndSave()` stops the recording, saves the file path to `_pendingPreviewPath`, and disposes the controller. On `resumed`, it navigates to the preview screen with the saved path:

```dart
@override
void didChangeAppLifecycleState(AppLifecycleState state) {
  if (state == AppLifecycleState.inactive) {
    if (_isRecording) {
      _finishRecordingAndSave();
      return;
    }
    _controller?.dispose();
    _controller = null;
    if (mounted) setState(() => _isInitializing = true);
  } else if (state == AppLifecycleState.resumed) {
    if (_pendingPreviewPath != null) {
      final path = _pendingPreviewPath!;
      _pendingPreviewPath = null;
      _navigateToPreview(path, isVideo: true);
    } else if (_controller == null) {
      _initCamera();
    }
  }
}
```

### 2. Camera Initialization and Controller Setup

Camera initialization discovers available cameras, then calls `_setupController` which creates a `CameraController` with `ResolutionPreset.high`, audio enabled, and JPEG format. It queries min/max zoom levels after initialization:

```dart
Future<void> _setupController(CameraDescription camera) async {
  final previousController = _controller;
  final controller = CameraController(
    camera,
    ResolutionPreset.high,
    enableAudio: true,
    imageFormatGroup: ImageFormatGroup.jpeg,
  );
  await previousController?.dispose();

  if (!mounted) return;
  _controller = controller;

  try {
    await controller.initialize();
    await controller.setFlashMode(_flashMode);
    _minZoom = await controller.getMinZoomLevel();
    _maxZoom = await controller.getMaxZoomLevel();
    _currentZoom = _minZoom;
    if (!mounted) return;
    setState(() => _isInitializing = false);
  } catch (e) {
    setState(() {
      _errorMessage = 'Failed to initialize camera';
      _isInitializing = false;
    });
  }
}
```

### 3. Flash Toggle (Off → Auto → On Cycle)

Flash cycles through three modes. Disabled when front camera is active:

```dart
Future<void> _toggleFlash() async {
  HapticFeedback.lightImpact();
  final modes = [FlashMode.off, FlashMode.auto, FlashMode.always];
  final nextIndex = (modes.indexOf(_flashMode) + 1) % modes.length;
  _flashMode = modes[nextIndex];
  try {
    await _controller?.setFlashMode(_flashMode);
    setState(() {});
  } catch (e) {
    debugPrint('Failed to set flash mode: $e');
  }
}
```

### 4. Recording with Timer and Auto-Stop

Video recording uses `Timer.periodic` to count seconds. When `_maxRecordingSeconds` (300s) is reached, recording auto-stops. Flash is switched to torch mode during video recording:

```dart
Future<void> _startRecording() async {
  if (_controller!.value.isRecordingVideo) return;
  HapticFeedback.mediumImpact();

  try {
    if (_flashMode != FlashMode.off) {
      await _controller!.setFlashMode(FlashMode.torch);
    }
    await _controller!.startVideoRecording();
    setState(() { _isRecording = true; _recordingSeconds = 0; });
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _recordingSeconds++;
      if (_recordingSeconds >= _maxRecordingSeconds) {
        _stopRecording();
        return;
      }
      setState(() {});
    });
  } catch (e) {
    debugPrint('Error starting recording: $e');
  }
}
```

### 5. Zoom — Pinch and Slider

Pinch-to-zoom uses `GestureDetector.onScaleStart/onScaleUpdate`. A `Slider` widget also provides zoom control with a numeric label:

```dart
void _onScaleStart(ScaleStartDetails details) {
  _pinchZoomStart = _currentZoom;
}

Future<void> _onScaleUpdate(ScaleUpdateDetails details) async {
  if (_controller == null) return;
  final newZoom = (_pinchZoomStart * details.scale).clamp(_minZoom, _maxZoom);
  if (newZoom == _currentZoom) return;
  _currentZoom = newZoom;
  await _controller!.setZoomLevel(_currentZoom);
  setState(() {});
}
```

### 6. Camera Controls Widgets

Extracted into `camera_controls.dart` for reuse. Includes a `CaptureMode` enum and three stateless widgets:

```dart
enum CaptureMode { photo, video }

class CameraCircleButton extends StatelessWidget {
  final IconData icon;
  final String? label;
  final VoidCallback? onTap;
  // Renders a 44×44 translucent circle with icon + optional label below
}

class CameraModeTab extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;
  // Animated dot indicator below the active mode label
}

class CameraCaptureButton extends StatelessWidget {
  final CaptureMode mode;
  final bool isRecording;
  final VoidCallback onTap;
  // 80×80 circle with animated inner shape: white circle for photo,
  // red/accent fill for video, rounded square when recording
}
```

### 7. Media Preview Screen

Displays captured or gallery-selected media with video playback (looping, play/pause tap overlay) or static photo. Handles lifecycle (pause/dispose on background, reinit on resume). Returns result as `Map<String, dynamic>` to caller:

```dart
class MediaPreviewScreen extends StatefulWidget {
  final String filePath;
  final bool isVideo;
  final bool fromGallery;  // Changes "Retake" label to "Re-select"
}

// On confirm:
void _useMedia() {
  Navigator.of(context).pop({
    'filePath': widget.filePath,
    'isVideo': widget.isVideo,
  });
}
```

Video error state shows a retry button; loading state shows a spinner.

### 8. Submit Screen — Entry Point and Permissions

`SubmitScreen` is the tab entry point. It requests camera + microphone permissions before launching `CameraScreen`. For gallery, it shows a bottom sheet to choose photo or video, then picks via `ImagePicker`:

```dart
Future<void> _openCamera() async {
  final cameraStatus = await Permission.camera.request();
  final micStatus = await Permission.microphone.request();

  if (!mounted) return;
  if (cameraStatus.isDenied || micStatus.isDenied) {
    _showPermissionDeniedSnackBar();
    return;
  }
  if (cameraStatus.isPermanentlyDenied || micStatus.isPermanentlyDenied) {
    _showSettingsDialog();
    return;
  }

  final result = await Navigator.of(context).push<Map<String, dynamic>>(
    MaterialPageRoute(builder: (_) => const CameraScreen()),
  );

  if (result != null && mounted) {
    _navigateToDetails(
      filePath: result['filePath'] as String,
      isVideo: result['isVideo'] as bool,
    );
  }
}
```

Permanently denied permissions show an `AlertDialog` with "Open Settings" that calls `openAppSettings()`.

## Complete Submit Flow
```
SubmitScreen (tap "Open Camera" or "Upload from Gallery")
    │
    ├── Camera path:
    │   Permission request → CameraScreen → MediaPreviewScreen
    │
    ├── Gallery path:
    │   Media type sheet → ImagePicker → MediaPreviewScreen
    │
    ▼
ReportDetailsScreen (Milestone 11)
    │ (submit)
    ▼
Pop to SubmitScreen → success SnackBar
```

## Testing
No dedicated test files were created for camera functionality. Manual testing required for:
- Camera initialization on devices with varying camera hardware
- Recording lifecycle (backgrounding mid-recording)
- Permission denied/permanently denied flows
- Gallery picker edge cases (cancellation, large files)

## Notes
- **Deviation from plan:** The original plan used `onLongPress` for video recording; the implementation uses a tap-to-toggle approach via `_toggleRecording()` instead, which is more accessible.
- **Deviation from plan:** `SubmitScreen` was built as a full entry point with gallery upload support (not planned in original milestone), including a media type bottom sheet.
- **Deviation from plan:** The `fromGallery` flag on `MediaPreviewScreen` changes the retake button label to "Re-select" for better UX.
- `PopScope` prevents back navigation during recording; instead it finishes the recording and navigates to preview.
- Temporary files are cleaned up (deleted) when the user goes back from preview without confirming.
- Flash is automatically disabled when switching to front camera.
- All UI uses the centralized theme system (`AppColors`, `AppTypography`, `AppSpacing`) rather than hardcoded values.
