import 'package:flutter/material.dart';
import 'package:camera/camera.dart';

class CameraWidget extends StatefulWidget {
  final bool showCamera;
  final VoidCallback? onToggleCamera;
  final void Function(
    CameraImage image,
    int rotationDegrees,
    bool isFrontCamera,
  )?
  onImage;

  // New: configurable capture settings
  final ResolutionPreset resolution;
  final ImageFormatGroup imageFormat;
  // New: throttle frames before invoking onImage (e.g., 15)
  final int maxFps;

  const CameraWidget({
    super.key,
    required this.showCamera,
    this.onToggleCamera,
    this.onImage,
    this.resolution = ResolutionPreset.low, // was medium
    this.imageFormat = ImageFormatGroup.yuv420, // was nv21
    this.maxFps = 15, // drop frames to ~15 FPS
  });

  @override
  State<CameraWidget> createState() => _CameraWidgetState();
}

class _CameraWidgetState extends State<CameraWidget> {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  bool _init = false;
  int _rotationDegrees = 0;
  bool _isFrontCamera = false;

  int _lastYieldMs = 0;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    _cameras = await availableCameras();
    final front = _cameras!.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => _cameras!.first,
    );
    _isFrontCamera = front.lensDirection == CameraLensDirection.front;

    _controller = CameraController(
      front,
      widget.resolution,
      enableAudio: false,
      imageFormatGroup: widget.imageFormat,
    );
    await _controller!.initialize();
    _rotationDegrees = _controller!.description.sensorOrientation;

    if (mounted) setState(() => _init = true);

    await _maybeStartStream();
  }

  Future<void> _maybeStartStream() async {
    if (!widget.showCamera || widget.onImage == null) return;
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (_controller!.value.isStreamingImages) return;

    // Reset throttle on (re)start
    _lastYieldMs = 0;

    await _controller!.startImageStream((frame) {
      // Throttle frames before sending to onImage
      final now = DateTime.now().millisecondsSinceEpoch;
      final minIntervalMs = (1000 / widget.maxFps).floor();
      if (_lastYieldMs != 0 && now - _lastYieldMs < minIntervalMs) return;

      _lastYieldMs = now;
      widget.onImage?.call(frame, _rotationDegrees, _isFrontCamera);
    });
  }

  Future<void> _stopStream() async {
    if (_controller?.value.isStreamingImages == true) {
      await _controller?.stopImageStream();
    }
  }

  @override
  void didUpdateWidget(covariant CameraWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Start/stop streaming when visibility or callback changes
    if (oldWidget.showCamera != widget.showCamera ||
        oldWidget.onImage != widget.onImage ||
        oldWidget.maxFps != widget.maxFps) {
      if (widget.showCamera && widget.onImage != null) {
        _maybeStartStream();
      } else {
        _stopStream();
      }
    }

    // If resolution or image format changed, recreate controller
    final captureChanged =
        oldWidget.resolution != widget.resolution ||
        oldWidget.imageFormat != widget.imageFormat;
    if (captureChanged) {
      _recreateController();
    }
  }

  Future<void> _recreateController() async {
    await _stopStream();
    await _controller?.dispose();
    _init = false;
    if (mounted) setState(() {});
    await _initCamera();
  }

  @override
  void dispose() {
    _stopStream();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = _controller;
    if (!widget.showCamera || !_init || ctrl == null) {
      return const SizedBox.expand(
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final size = ctrl.value.previewSize;
    if (size == null) {
      return const SizedBox.expand(
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final previewW = size.height;
    final previewH = size.width;

    return Stack(
      fit: StackFit.expand,
      children: [
        FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: previewW,
            height: previewH,
            child: CameraPreview(ctrl),
          ),
        ),
        Positioned(
          top: 12,
          right: 12,
          child: IconButton(
            onPressed: widget.onToggleCamera,
            icon: const Icon(Icons.close, color: Colors.white),
          ),
        ),
      ],
    );
  }
}
