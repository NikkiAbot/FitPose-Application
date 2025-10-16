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

  const CameraWidget({
    super.key,
    required this.showCamera,
    this.onToggleCamera,
    this.onImage,
  });

  @override
  State<CameraWidget> createState() => _CameraWidgetState();
}

class _CameraWidgetState extends State<CameraWidget>
    with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  bool _init = false;
  int _rotationDegrees = 0;
  bool _isFrontCamera = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
  }

  Future<void> _initCamera() async {
    _cameras = await availableCameras();

    final selected = _cameras!.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => _cameras!.first,
    );

    _isFrontCamera = selected.lensDirection == CameraLensDirection.front;

    _controller = CameraController(
      selected,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.nv21,
    );

    await _controller!.initialize();
    _rotationDegrees = _controller!.description.sensorOrientation;

    // ignore: use_build_context_synchronously
    final orientation = MediaQuery.of(context).orientation;
    _rotationDegrees = (orientation == Orientation.portrait) ? 0 : 90;

    if (widget.onImage != null && !_controller!.value.isStreamingImages) {
      await _controller!.startImageStream((frame) {
        widget.onImage?.call(frame, _rotationDegrees, _isFrontCamera);
      });
    }

    if (mounted) setState(() => _init = true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final CameraController? cameraController = _controller;

    if (cameraController == null || !cameraController.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive) {
      cameraController.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_controller?.value.isStreamingImages == true) {
      _controller?.stopImageStream();
    }
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

    final previewSize = ctrl.value.previewSize;
    if (previewSize == null) {
      return const SizedBox.expand(
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final isPortrait =
        MediaQuery.of(context).orientation == Orientation.portrait;
    final cameraAspect =
        isPortrait
            ? previewSize.height / previewSize.width
            : previewSize.width / previewSize.height;

    return LayoutBuilder(
      builder: (context, constraints) {
        final screenAspect = constraints.maxWidth / constraints.maxHeight;
        double scale = 1.0;

        // 🔧 Adjust scale to cover the entire screen with correct aspect ratio
        if (screenAspect > cameraAspect) {
          // screen is wider than camera preview
          scale = screenAspect / cameraAspect;
        } else {
          // screen is taller than camera preview
          scale = cameraAspect / screenAspect;
        }

        return Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: Transform.scale(scale: scale, child: CameraPreview(ctrl)),
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
      },
    );
  }
}
