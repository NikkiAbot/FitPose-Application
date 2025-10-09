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

class _CameraWidgetState extends State<CameraWidget> {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  bool _init = false;
  int _rotationDegrees = 0;
  bool _isFrontCamera = false;

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
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.nv21,
    );
    await _controller!.initialize();
    _rotationDegrees = _controller!.description.sensorOrientation;

    if (widget.onImage != null && !_controller!.value.isStreamingImages) {
      await _controller!.startImageStream((frame) {
        widget.onImage?.call(frame, _rotationDegrees, _isFrontCamera);
      });
    }

    if (mounted) setState(() => _init = true);
  }

  @override
  void dispose() {
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
