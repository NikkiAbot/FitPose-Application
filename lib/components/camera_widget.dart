import 'package:flutter/material.dart';
import 'package:camera/camera.dart';

class CameraWidget extends StatefulWidget {
  final bool showCamera;
  final VoidCallback? onToggleCamera;

  const CameraWidget({
    super.key,
    required this.showCamera,
    this.onToggleCamera,
  });

  @override
  State<CameraWidget> createState() => _CameraWidgetState();
}

class _CameraWidgetState extends State<CameraWidget> {
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  bool _isCameraInitialized = false;

  @override
  void initState() {
    super.initState();
    if (widget.showCamera) {
      _initializeCamera();
    }
  }

  @override
  void didUpdateWidget(CameraWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.showCamera && !oldWidget.showCamera) {
      _initializeCamera();
    } else if (!widget.showCamera && oldWidget.showCamera) {
      _disposeCamera();
    }
  }

  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras != null && _cameras!.isNotEmpty) {
        // Always use front camera for posture detection
        CameraDescription? frontCamera;

        // Look for front-facing camera (laptop webcam/selfie camera)
        for (final camera in _cameras!) {
          if (camera.lensDirection == CameraLensDirection.front) {
            frontCamera = camera;
            break;
          }
        }

        // If no front camera found, use external camera as fallback
        if (frontCamera == null) {
          for (final camera in _cameras!) {
            if (camera.lensDirection == CameraLensDirection.external) {
              frontCamera = camera;
              break;
            }
          }
        }

        // Use first available camera if no front or external camera found
        frontCamera ??= _cameras![0];

        _cameraController = CameraController(
          frontCamera,
          ResolutionPreset.high,
          enableAudio: false, // No audio needed for posture detection
        );

        await _cameraController!.initialize();
        if (mounted) {
          setState(() {
            _isCameraInitialized = true;
          });
        }

        // Show success message for posture detection
        _showSuccessSnackBar('Camera ready for posture detection');
      }
    } catch (e) {
      print('Error initializing camera: $e');
      if (mounted) {
        _showErrorSnackBar('Failed to initialize camera: $e');
      }
    }
  }

  Future<void> _disposeCamera() async {
    await _cameraController?.dispose();
    _cameraController = null;
    if (mounted) {
      setState(() {
        _isCameraInitialized = false;
      });
    }
  }

  void _showSuccessSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _showErrorSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  void dispose() {
    _disposeCamera();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.showCamera) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child:
            _isCameraInitialized && _cameraController != null
                ? CameraPreview(_cameraController!)
                : Container(
                  color: Colors.black,
                  child: const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                        SizedBox(height: 16),
                        Text(
                          'Initializing camera for posture detection...',
                          style: TextStyle(fontSize: 16, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ),
      ),
    );
  }
}
