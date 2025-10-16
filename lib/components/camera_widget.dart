import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';

/// Non-mirrored camera preview with optional fixed rotation for HPE.
/// - Android format: YUV420
/// - iOS format: BGRA8888
///
/// Set [forcedRotationDegrees] to 90 for portrait workouts (most of yours),
/// and to 0 for landscape workouts (e.g., plank/push-up) if needed.
class CameraWidget extends StatefulWidget {
  final bool showCamera;
  final VoidCallback? onToggleCamera;
  final void Function(
    CameraImage image,
    int rotationDegrees,
    bool isFrontCamera,
  )? onImage;

  /// If provided, the value (0/90/180/270) is passed to onImage every frame.
  /// This bypasses device/sensor rotation logic for stability.
  final int? forcedRotationDegrees;

  /// Lock capture orientation to portraitUp (helps keep rotation stable).
  /// Turn off for landscape-only pages.
  final bool lockToPortrait;

  final bool showSwitchCameraButton;

  const CameraWidget({
    super.key,
    required this.showCamera,
    this.onToggleCamera,
    this.onImage,
    this.forcedRotationDegrees, // e.g., 90 for most exercises
    this.lockToPortrait = true, // portrait lock by default
    this.showSwitchCameraButton = true,
  });

  @override
  State<CameraWidget> createState() => _CameraWidgetState();
}

class _CameraWidgetState extends State<CameraWidget> with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription> _cameras = const [];

  bool _initialized = false;
  bool _isFrontCamera = false;
  bool _processing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
  }

  @override
  void didUpdateWidget(covariant CameraWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_controller == null) return;
    if (widget.showCamera) {
      _startStreamIfNeeded();
    } else {
      _stopStreamIfNeeded();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final ctrl = _controller;
    if (ctrl == null) return;

    if (state == AppLifecycleState.paused) {
      _stopStreamIfNeeded();
    } else if (state == AppLifecycleState.resumed) {
      if (widget.showCamera) _startStreamIfNeeded();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopStreamIfNeeded();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) throw 'No cameras available';

      // Prefer front camera first; change if you want back by default
      final preferred = _cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => _cameras.first,
      );

      await _startWithDescription(preferred);

      if (!mounted) return;
      setState(() => _initialized = true);

      if (widget.showCamera) _startStreamIfNeeded();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Camera error: $e')),
      );
    }
  }

  Future<void> _startWithDescription(CameraDescription desc) async {
    // ML Kit–friendly formats
    final imgFormat = Platform.isIOS
        ? ImageFormatGroup.bgra8888
        : ImageFormatGroup.yuv420;

    await _controller?.dispose();

    final controller = CameraController(
      desc,
      ResolutionPreset.medium, // lower for more FPS if needed
      enableAudio: false,
      imageFormatGroup: imgFormat,
    );

    _controller = controller;
    await controller.initialize();

    // Lock to portrait if requested (stabilizes rotation)
    if (widget.lockToPortrait) {
      try {
        await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
      } catch (_) {
        // Some platforms/cameras may not support lock; ignore.
      }
    }

    _isFrontCamera = controller.description.lensDirection == CameraLensDirection.front;
  }

  void _startStreamIfNeeded() {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    if (widget.onImage == null) return;
    if (ctrl.value.isStreamingImages) return;

    ctrl.startImageStream((frame) async {
      if (_processing) return;
      _processing = true;

      try {
        // Use forcedRotation if provided; else compute from device/sensor.
        final rotation =
            widget.forcedRotationDegrees ?? _computeRotationDegrees(ctrl);

        widget.onImage?.call(frame, rotation, _isFrontCamera);
      } catch (_) {
        // keep stream alive on frame errors
      } finally {
        _processing = false;
      }
    });
  }

  Future<void> _stopStreamIfNeeded() async {
    final ctrl = _controller;
    if (ctrl == null) return;
    if (ctrl.value.isStreamingImages) {
      try {
        await ctrl.stopImageStream();
      } catch (_) {}
    }
  }

  int _computeRotationDegrees(CameraController ctrl) {
    // If you use forcedRotationDegrees, we never call this.
    final sensor = ctrl.description.sensorOrientation; // 0/90/180/270
    final devOri = ctrl.value.deviceOrientation;
    int device;
    switch (devOri) {
      case DeviceOrientation.portraitUp:
        device = 0;
        break;
      case DeviceOrientation.landscapeLeft:
        device = 270;
        break;
      case DeviceOrientation.portraitDown:
        device = 180;
        break;
      case DeviceOrientation.landscapeRight:
        device = 90;
        break;
      default:
        device = 0;
    }
    int rot = (sensor - device) % 360;
    if (rot < 0) rot += 360;
    return rot;
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2) return;
    final current = _controller?.description;
    if (current == null) return;

    final next = _cameras.firstWhere(
      (c) => c.lensDirection != current.lensDirection,
      orElse: () => current,
    );

    await _stopStreamIfNeeded();
    await _startWithDescription(next);

    if (!mounted) return;
    setState(() => _initialized = _controller?.value.isInitialized ?? false);

    if (widget.showCamera) _startStreamIfNeeded();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = _controller;

    if (!widget.showCamera || !_initialized || ctrl == null || !ctrl.value.isInitialized) {
      return const SizedBox.expand(child: Center(child: CircularProgressIndicator()));
    }

    final size = ctrl.value.previewSize;
    if (size == null) {
      return const SizedBox.expand(child: Center(child: CircularProgressIndicator()));
    }

    // Size from plugin is sensor coords; swap for portrait display
    final previewW = size.height;
    final previewH = size.width;

    return Stack(
      fit: StackFit.expand,
      children: [
        // TRUE (non-mirrored) preview for both front/back
        FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: previewW,
            height: previewH,
            child: CameraPreview(ctrl), // No Transform → true image
          ),
        ),

        // Close
        Positioned(
          top: 12,
          right: 12,
          child: IconButton(
            tooltip: 'Close camera',
            onPressed: widget.onToggleCamera,
            icon: const Icon(Icons.close, color: Colors.white),
          ),
        ),

        // Switch camera
        if (widget.showSwitchCameraButton)
          Positioned(
            right: 12,
            bottom: 20,
            child: Material(
              color: Colors.black.withOpacity(0.35),
              shape: const CircleBorder(),
              child: IconButton(
                tooltip: 'Switch camera',
                onPressed: _switchCamera,
                icon: const Icon(Icons.cameraswitch, color: Colors.white),
              ),
            ),
          ),
      ],
    );
  }
}
