import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/theme.dart';
import 'media_preview_screen.dart';

/// Capture mode: photo or video.
enum CaptureMode { photo, video }

/// Full-screen camera for capturing crime report evidence.
class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  int _currentCameraIndex = 0;
  bool _isInitializing = true;
  String? _errorMessage;

  CaptureMode _mode = CaptureMode.video;
  bool _isRecording = false;
  FlashMode _flashMode = FlashMode.off;

  // Recording timer
  Timer? _recordingTimer;
  int _recordingSeconds = 0;

  // Zoom
  double _minZoom = 1.0;
  double _maxZoom = 1.0;
  double _currentZoom = 1.0;
  double _pinchZoomStart = 1.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _recordingTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_controller == null || !_controller!.value.isInitialized) return;

    if (state == AppLifecycleState.inactive) {
      _controller?.dispose();
      _controller = null;
      if (mounted) setState(() => _isInitializing = true);
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  Future<void> _initCamera() async {
    setState(() {
      _isInitializing = true;
      _errorMessage = null;
    });

    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        setState(() {
          _errorMessage = 'No cameras available on this device';
          _isInitializing = false;
        });
        return;
      }

      await _setupController(_cameras[_currentCameraIndex]);
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to initialize camera';
        _isInitializing = false;
      });
    }
  }

  Future<void> _setupController(CameraDescription camera) async {
    final previousController = _controller;
    final controller = CameraController(
      camera,
      ResolutionPreset.high,
      enableAudio: true,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    // Dispose the old controller after creating the new one
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

  // --- Actions ---

  Future<void> _flipCamera() async {
    if (_cameras.length < 2) return;
    HapticFeedback.lightImpact();

    final currentDirection = _cameras[_currentCameraIndex].lensDirection;
    final targetDirection = currentDirection == CameraLensDirection.back
        ? CameraLensDirection.front
        : CameraLensDirection.back;

    final targetIndex = _cameras.indexWhere(
      (c) => c.lensDirection == targetDirection,
    );
    if (targetIndex == -1) return;

    _currentCameraIndex = targetIndex;
    await _setupController(_cameras[_currentCameraIndex]);
  }

  Future<void> _toggleFlash() async {
    HapticFeedback.lightImpact();
    final modes = [FlashMode.off, FlashMode.auto, FlashMode.always];
    final nextIndex = (modes.indexOf(_flashMode) + 1) % modes.length;
    _flashMode = modes[nextIndex];

    try {
      await _controller?.setFlashMode(_flashMode);
      setState(() {});
    } catch (_) {}
  }

  void _onScaleStart(ScaleStartDetails details) {
    _pinchZoomStart = _currentZoom;
  }

  Future<void> _onScaleUpdate(ScaleUpdateDetails details) async {
    if (_controller == null) return;

    final newZoom = (_pinchZoomStart * details.scale)
        .clamp(_minZoom, _maxZoom);

    if (newZoom == _currentZoom) return;

    _currentZoom = newZoom;
    await _controller!.setZoomLevel(_currentZoom);
    setState(() {});
  }

  Future<void> _setZoom(double zoom) async {
    if (_controller == null) return;

    _currentZoom = zoom.clamp(_minZoom, _maxZoom);
    await _controller!.setZoomLevel(_currentZoom);
    setState(() {});
  }

  Future<void> _takePhoto() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (_controller!.value.isTakingPicture) return;

    HapticFeedback.mediumImpact();

    try {
      final file = await _controller!.takePicture();
      if (!mounted) return;
      _navigateToPreview(file.path, isVideo: false);
    } catch (e) {
      debugPrint('Error taking photo: $e');
    }
  }

  Future<void> _toggleRecording() async {
    if (_controller == null || !_controller!.value.isInitialized) return;

    if (_isRecording) {
      await _stopRecording();
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    if (_controller!.value.isRecordingVideo) return;

    HapticFeedback.mediumImpact();

    try {
      // Enable torch for video if flash is on
      if (_flashMode != FlashMode.off) {
        await _controller!.setFlashMode(FlashMode.torch);
      }

      await _controller!.startVideoRecording();
      setState(() {
        _isRecording = true;
        _recordingSeconds = 0;
      });
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        setState(() => _recordingSeconds++);
      });
    } catch (e) {
      debugPrint('Error starting recording: $e');
    }
  }

  Future<void> _stopRecording() async {
    if (!_controller!.value.isRecordingVideo) return;

    HapticFeedback.mediumImpact();
    _recordingTimer?.cancel();

    try {
      final file = await _controller!.stopVideoRecording();
      setState(() => _isRecording = false);

      // Restore flash mode from torch back to the user's setting
      await _controller!.setFlashMode(_flashMode);

      if (!mounted) return;
      _navigateToPreview(file.path, isVideo: true);
    } catch (e) {
      setState(() => _isRecording = false);
      debugPrint('Error stopping recording: $e');
    }
  }

  void _navigateToPreview(String filePath, {required bool isVideo}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MediaPreviewScreen(
          filePath: filePath,
          isVideo: isVideo,
        ),
      ),
    ).then((result) {
      // If preview returned 'use', pop back to submit screen with the path
      if (result is Map<String, dynamic>) {
        Navigator.of(context).pop(result);
      }
    });
  }

  String _formatDuration(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  IconData get _flashIcon {
    switch (_flashMode) {
      case FlashMode.off:
        return Icons.flash_off_rounded;
      case FlashMode.auto:
        return Icons.flash_auto_rounded;
      case FlashMode.always:
        return Icons.flash_on_rounded;
      case FlashMode.torch:
        return Icons.flash_on_rounded;
    }
  }

  String get _flashLabel {
    switch (_flashMode) {
      case FlashMode.off:
        return 'Off';
      case FlashMode.auto:
        return 'Auto';
      case FlashMode.always:
        return 'On';
      case FlashMode.torch:
        return 'Torch';
    }
  }

  // --- Build ---

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
    );

    return Scaffold(
      backgroundColor: Colors.black,
      body: _isInitializing
          ? _buildLoading()
          : _errorMessage != null
              ? _buildError()
              : _buildCamera(),
    );
  }

  Widget _buildLoading() {
    return const Center(
      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.videocam_off_rounded, color: AppColors.textTertiary, size: 64),
            const SizedBox(height: AppSpacing.md),
            Text(
              _errorMessage!,
              style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.lg),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Go Back', style: TextStyle(color: AppColors.primary)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCamera() {
    final controller = _controller!;
    final topPadding = MediaQuery.of(context).padding.top;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return GestureDetector(
      onScaleStart: _onScaleStart,
      onScaleUpdate: _onScaleUpdate,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Camera preview (scaled to cover)
          Center(
            child: AspectRatio(
              aspectRatio: 1 / controller.value.aspectRatio,
              child: CameraPreview(controller),
            ),
          ),

          // Top bar
          Positioned(
            top: topPadding + AppSpacing.sm,
            left: AppSpacing.md,
            right: AppSpacing.md,
            child: _buildTopBar(),
          ),

          // Recording timer
          if (_isRecording)
            Positioned(
              top: topPadding + 60,
              left: 0,
              right: 0,
              child: _buildRecordingTimer(),
            ),

          // Zoom slider
          if (_maxZoom > _minZoom)
            Positioned(
              bottom: bottomPadding + 180,
              left: AppSpacing.xl,
              right: AppSpacing.xl,
              child: _buildZoomSlider(),
            ),

          // Bottom controls
          Positioned(
            bottom: bottomPadding + AppSpacing.lg,
            left: 0,
            right: 0,
            child: _buildBottomControls(),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Close
        _CircleButton(
          icon: Icons.close_rounded,
          onTap: () {
            if (_isRecording) return;
            Navigator.of(context).pop();
          },
        ),

        // Flash
        _CircleButton(
          icon: _flashIcon,
          label: _flashLabel,
          onTap: _isRecording ? null : _toggleFlash,
        ),

        // Flip camera
        _CircleButton(
          icon: Icons.flip_camera_ios_rounded,
          onTap: (_isRecording || _cameras.length < 2) ? null : _flipCamera,
        ),
      ],
    );
  }

  Widget _buildRecordingTimer() {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.primary.withAlpha(200),
          borderRadius: BorderRadius.circular(AppSpacing.radiusRound),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _formatDuration(_recordingSeconds),
              style: AppTypography.labelMedium.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildZoomSlider() {
    return Row(
      children: [
        const Icon(Icons.photo_size_select_small, color: Colors.white70, size: 16),
        const SizedBox(width: 8),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              activeTrackColor: Colors.white,
              inactiveTrackColor: Colors.white24,
              thumbColor: Colors.white,
              overlayColor: Colors.white24,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              trackHeight: 2,
            ),
            child: Slider(
              value: _currentZoom,
              min: _minZoom,
              max: _maxZoom,
              onChanged: _setZoom,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.black45,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            '${_currentZoom.toStringAsFixed(1)}x',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomControls() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Mode toggle
        if (!_isRecording)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.lg),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _ModeTab(
                  label: 'Photo',
                  isActive: _mode == CaptureMode.photo,
                  onTap: () => setState(() => _mode = CaptureMode.photo),
                ),
                const SizedBox(width: AppSpacing.xl),
                _ModeTab(
                  label: 'Video',
                  isActive: _mode == CaptureMode.video,
                  onTap: () => setState(() => _mode = CaptureMode.video),
                ),
              ],
            ),
          ),

        // Capture button
        _CaptureButton(
          mode: _mode,
          isRecording: _isRecording,
          onTap: _mode == CaptureMode.photo ? _takePhoto : _toggleRecording,
        ),
      ],
    );
  }
}

// --- Sub-widgets ---

class _CircleButton extends StatelessWidget {
  final IconData icon;
  final String? label;
  final VoidCallback? onTap;

  const _CircleButton({required this.icon, this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDisabled = onTap == null;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.black.withAlpha(100),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: isDisabled ? Colors.white38 : Colors.white,
              size: 24,
            ),
          ),
          if (label != null) ...[
            const SizedBox(height: 4),
            Text(
              label!,
              style: AppTypography.caption.copyWith(
                color: Colors.white70,
                fontSize: 10,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ModeTab extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _ModeTab({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: AppTypography.titleSmall.copyWith(
              color: isActive ? Colors.white : Colors.white54,
              fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
          const SizedBox(height: 4),
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: isActive ? 6 : 0,
            height: 6,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }
}

class _CaptureButton extends StatelessWidget {
  final CaptureMode mode;
  final bool isRecording;
  final VoidCallback onTap;

  const _CaptureButton({
    required this.mode,
    required this.isRecording,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.white,
            width: 4,
          ),
        ),
        padding: const EdgeInsets.all(4),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: isRecording ? 32 : 64,
          height: isRecording ? 32 : 64,
          decoration: BoxDecoration(
            color: mode == CaptureMode.video
                ? AppColors.primary
                : Colors.white,
            borderRadius: BorderRadius.circular(isRecording ? 8 : 32),
          ),
        ),
      ),
    );
  }
}
