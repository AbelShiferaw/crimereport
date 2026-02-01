# Milestone 10: Submit Report - Camera

## Goal
Build the camera screen for capturing video/photo evidence when submitting a crime report.

## Dependencies
Requires **Milestone 1** complete (project structure with camera package).

## Implementation

### 1. Camera Screen
```dart
// lib/features/submit/presentation/camera_screen.dart
class CameraScreen extends StatefulWidget {
  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  bool _isRecording = false;
  bool _isVideo = true; // Toggle between video/photo mode
  
  @override
  void initState() {
    super.initState();
    _initCamera();
  }
  
  Future<void> _initCamera() async {
    _cameras = await availableCameras();
    if (_cameras!.isEmpty) return;
    
    _controller = CameraController(
      _cameras!.first, // Back camera
      ResolutionPreset.high,
      enableAudio: true,
    );
    
    await _controller!.initialize();
    setState(() {});
  }
  
  @override
  Widget build(BuildContext context) {
    if (_controller == null || !_controller!.value.isInitialized) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      );
    }
    
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Camera preview
          CameraPreview(_controller!),
          
          // Top bar (close, flash, flip)
          _buildTopBar(),
          
          // Bottom controls
          _buildBottomControls(),
        ],
      ),
    );
  }
}
```

### 2. Top Bar Controls
```dart
Widget _buildTopBar() {
  return Positioned(
    top: MediaQuery.of(context).padding.top + 8,
    left: 16,
    right: 16,
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Close button
        IconButton(
          onPressed: () => Navigator.pop(context),
          icon: Icon(Icons.close, color: Colors.white, size: 28),
        ),
        
        // Flash toggle
        IconButton(
          onPressed: _toggleFlash,
          icon: Icon(
            _flashMode == FlashMode.off ? Icons.flash_off : Icons.flash_on,
            color: Colors.white,
          ),
        ),
        
        // Flip camera
        IconButton(
          onPressed: _flipCamera,
          icon: Icon(Icons.flip_camera_ios, color: Colors.white),
        ),
      ],
    ),
  );
}
```

### 3. Bottom Controls (Capture Button)
```dart
Widget _buildBottomControls() {
  return Positioned(
    bottom: 40,
    left: 0,
    right: 0,
    child: Column(
      children: [
        // Video/Photo toggle
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _ModeButton(
              label: 'Photo',
              isActive: !_isVideo,
              onTap: () => setState(() => _isVideo = false),
            ),
            SizedBox(width: 24),
            _ModeButton(
              label: 'Video',
              isActive: _isVideo,
              onTap: () => setState(() => _isVideo = true),
            ),
          ],
        ),
        SizedBox(height: 24),
        
        // Capture button
        GestureDetector(
          onTap: _isVideo ? null : _takePhoto,
          onLongPressStart: _isVideo ? (_) => _startRecording() : null,
          onLongPressEnd: _isVideo ? (_) => _stopRecording() : null,
          child: AnimatedContainer(
            duration: Duration(milliseconds: 200),
            width: _isRecording ? 80 : 72,
            height: _isRecording ? 80 : 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 4),
              color: _isRecording ? Colors.red : Colors.transparent,
            ),
            child: _isVideo
                ? Center(
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(_isRecording ? 4 : 12),
                      ),
                    ),
                  )
                : null,
          ),
        ),
      ],
    ),
  );
}
```

### 4. Capture Functions
```dart
Future<void> _takePhoto() async {
  final image = await _controller!.takePicture();
  _navigateToPreview(image.path, isVideo: false);
}

Future<void> _startRecording() async {
  await _controller!.startVideoRecording();
  setState(() => _isRecording = true);
}

Future<void> _stopRecording() async {
  final video = await _controller!.stopVideoRecording();
  setState(() => _isRecording = false);
  _navigateToPreview(video.path, isVideo: true);
}

void _navigateToPreview(String path, {required bool isVideo}) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => MediaPreviewScreen(
        filePath: path,
        isVideo: isVideo,
      ),
    ),
  );
}
```

### 5. Media Preview Screen
```dart
// lib/features/submit/presentation/media_preview_screen.dart
class MediaPreviewScreen extends StatelessWidget {
  final String filePath;
  final bool isVideo;
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Preview
          isVideo
              ? VideoPreviewPlayer(filePath: filePath)
              : Image.file(File(filePath), fit: BoxFit.contain),
          
          // Bottom buttons
          Positioned(
            bottom: 40,
            left: 24,
            right: 24,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Retake
                _ActionButton(
                  icon: Icons.refresh,
                  label: 'Retake',
                  onTap: () => Navigator.pop(context),
                ),
                
                // Use this
                _ActionButton(
                  icon: Icons.check,
                  label: 'Use',
                  isPrimary: true,
                  onTap: () => _proceedToDetails(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
```

## Deliverable Checklist
- [ ] Camera preview displays
- [ ] Can toggle video/photo mode
- [ ] Photo: tap to capture
- [ ] Video: hold to record
- [ ] Recording indicator (red button)
- [ ] Flash toggle works
- [ ] Camera flip works
- [ ] Preview shows captured media
- [ ] Retake returns to camera
- [ ] Use button proceeds to next step
- [ ] Proper permissions handling

## Files (3 total)
1. `lib/features/submit/presentation/camera_screen.dart` - Create
2. `lib/features/submit/presentation/media_preview_screen.dart` - Create
3. `lib/features/submit/presentation/submit_screen.dart` - Update to launch camera
