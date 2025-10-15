import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:onnxruntime/onnxruntime.dart';

import '../../components/camera_widget.dart';

class BicepCurl extends StatefulWidget {
  const BicepCurl({super.key});

  @override
  State<BicepCurl> createState() => _BicepCurlState();
}

class _BicepCurlState extends State<BicepCurl> {
  final bool _showCamera = true;

  // ML Kit pose detector
  late final PoseDetector _poseDetector = PoseDetector(
    options: PoseDetectorOptions(mode: PoseDetectionMode.stream),
  );

  // ONNX runtime
  OrtSession? _session;
  List<String> _labels = [];

  // Processing control
  bool _isProcessing = false;
  int _lastProcessMs = 0;
  static const int _procIntervalMs = 100; // ~10 FPS

  // Latest pose & image dims
  Pose? _latestPose;
  int? _imageWidth;
  int? _imageHeight;

  // Rotation from camera
  InputImageRotation _lastRotation = InputImageRotation.rotation0deg;

  // Feature histories
  final List<double> _elbowAngleHistory = [];
  final List<double> _elbowYHistory = [];
  static const int _historyMax = 16;

  // UI
  String _feedback = 'Loading model...';

  @override
  void initState() {
    super.initState();
    _loadModelAndLabels();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _showInstructionsDialog(),
    );
  }

  @override
  void dispose() {
    _poseDetector.close();
    try {
      _session?.release();
    } catch (_) {}
    super.dispose();
  }

  Future<void> _loadModelAndLabels() async {
    try {
      final rawModel = await rootBundle.load('assets/form_knn.onnx');

      // Create session without unsupported optimization APIs
      final modelBytes = rawModel.buffer.asUint8List();
      try {
        final opts = OrtSessionOptions();
        _session = OrtSession.fromBuffer(modelBytes, opts);
      } catch (_) {
        // Fallback if options ctor is not supported
        final fallbackOpts = OrtSessionOptions();
        _session = OrtSession.fromBuffer(modelBytes, fallbackOpts);
      }

      final labelData = await rootBundle.loadString('assets/form_labels.json');
      _labels = List<String>.from(jsonDecode(labelData));

      if (kDebugMode) debugPrint('[ONNX] Model and labels loaded.');
      setState(() => _feedback = 'Ready — perform curls');
    } catch (e) {
      if (kDebugMode) debugPrint('[ONNX] Load failed: $e');
      setState(() => _feedback = 'Model load failed');
    }
  }

  // CameraWidget callback
  void _onCameraImage(
    CameraImage image,
    int rotationDegrees,
    bool isFrontCamera,
  ) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_isProcessing || now - _lastProcessMs < _procIntervalMs) return;
    _isProcessing = true;
    _lastProcessMs = now;

    _lastRotation = _toImageRotation(rotationDegrees);

    _processPose(image).whenComplete(() {
      _isProcessing = false;
      if (mounted) setState(() {});
    });
  }

  InputImageRotation _toImageRotation(int deg) {
    switch (deg % 360) {
      case 0:
        return InputImageRotation.rotation0deg;
      case 90:
        return InputImageRotation.rotation90deg;
      case 180:
        return InputImageRotation.rotation180deg;
      case 270:
        return InputImageRotation.rotation270deg;
      default:
        return InputImageRotation.rotation0deg;
    }
  }

  Future<void> _processPose(CameraImage image) async {
    try {
      _imageWidth ??= image.width;
      _imageHeight ??= image.height;

      late final Uint8List bytes;
      late final InputImageFormat fmt;
      late final int bytesPerRow;

      if (Platform.isIOS) {
        // iOS: BGRA8888 in plane 0
        bytes = image.planes[0].bytes;
        fmt = InputImageFormat.bgra8888;
        bytesPerRow = image.planes[0].bytesPerRow;
      } else {
        // Android: YUV420_888 → NV21 for ML Kit
        bytes = _yuv420ToNv21(image);
        fmt = InputImageFormat.nv21;
        bytesPerRow = image.planes.first.bytesPerRow; // Y stride
      }

      final inputImage = InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: _lastRotation,
          format: fmt,
          bytesPerRow: bytesPerRow,
        ),
      );

      final poses = await _poseDetector.processImage(inputImage);
      if (poses.isEmpty) {
        _latestPose = null;
        _feedback = 'No pose detected';
        _elbowAngleHistory.clear();
        _elbowYHistory.clear();
        return;
      }

      _latestPose = poses.first;
      await _extractFeaturesAndRunModel(_latestPose!);
    } catch (e) {
      if (kDebugMode) debugPrint('[Pose] Exception: $e');
      _latestPose = null;
      _feedback = 'Error processing frame';
      _elbowAngleHistory.clear();
      _elbowYHistory.clear();
    }
  }

  // Convert YUV420 3-plane -> NV21 (Android)
  Uint8List _yuv420ToNv21(CameraImage image) {
    final width = image.width;
    final height = image.height;

    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];

    final ySize = width * height;
    final out = Uint8List(ySize + (ySize ~/ 2));

    // Copy Y with row stride
    int outIndex = 0;
    final yRowStride = yPlane.bytesPerRow;
    for (int row = 0; row < height; row++) {
      out.setRange(outIndex, outIndex + width, yPlane.bytes, row * yRowStride);
      outIndex += width;
    }

    // Interleave VU
    final chromaWidth = width ~/ 2;
    final chromaHeight = height ~/ 2;
    final uRowStride = uPlane.bytesPerRow;
    final vRowStride = vPlane.bytesPerRow;
    final uPixelStride = uPlane.bytesPerPixel ?? 1;
    final vPixelStride = vPlane.bytesPerPixel ?? 1;

    int uvOut = ySize;
    for (int row = 0; row < chromaHeight; row++) {
      for (int col = 0; col < chromaWidth; col++) {
        final uIndex = row * uRowStride + col * uPixelStride;
        final vIndex = row * vRowStride + col * vPixelStride;
        out[uvOut++] = vPlane.bytes[vIndex]; // V
        out[uvOut++] = uPlane.bytes[uIndex]; // U
      }
    }
    return out;
  }

  // Angle in degrees at b for a-b-c
  double _angleDeg(Offset a, Offset b, Offset c) {
    final ab = a - b;
    final cb = c - b;
    final dot = ab.dx * cb.dx + ab.dy * cb.dy;
    final denom = ab.distance * cb.distance;
    if (denom == 0) return 0;
    final cosv = (dot / denom).clamp(-1.0, 1.0);
    return (180 / math.pi) * math.acos(cosv);
    // Note: ML Kit coordinates are image-space; no Y flip needed for feature consistency.
  }

  Future<void> _extractFeaturesAndRunModel(Pose pose) async {
    final lm = pose.landmarks;

    final shoulderR = lm[PoseLandmarkType.rightShoulder];
    final elbowR = lm[PoseLandmarkType.rightElbow];
    final wristR = lm[PoseLandmarkType.rightWrist];
    final hipR = lm[PoseLandmarkType.rightHip];

    final shoulderL = lm[PoseLandmarkType.leftShoulder];
    final hipL = lm[PoseLandmarkType.leftHip];

    if (shoulderR == null || elbowR == null || wristR == null) {
      _feedback = 'Move into view';
      return;
    }

    final imgW = (_imageWidth ?? 1).toDouble();
    final imgH = (_imageHeight ?? 1).toDouble();

    // 1) Elbow angle (deg)
    final elbowAng = _angleDeg(
      Offset(shoulderR.x, shoulderR.y),
      Offset(elbowR.x, elbowR.y),
      Offset(wristR.x, wristR.y),
    );

    // 2) Elbow dx (normalized)
    final elbowDx = (elbowR.x - shoulderR.x) / imgW;

    // 3) Torso inclination (deg)
    double torsoIncl = 0;
    if (shoulderL != null && hipL != null && hipR != null) {
      final avgShoulder = Offset(
        (shoulderL.x + shoulderR.x) / 2,
        (shoulderL.y + shoulderR.y) / 2,
      );
      final avgHip = Offset((hipL.x + hipR.x) / 2, (hipL.y + hipR.y) / 2);
      final vec = avgShoulder - avgHip;
      torsoIncl = (180 / math.pi) * math.atan2(vec.dx.abs(), vec.dy.abs());
    } else if (hipR != null) {
      final vec = Offset(shoulderR.x - hipR.x, shoulderR.y - hipR.y);
      torsoIncl = (180 / math.pi) * math.atan2(vec.dx.abs(), vec.dy.abs());
    }

    // 4) Elbow vel (normalized Y delta)
    final currElbowY = elbowR.y;
    double elbowVel = 0;
    if (_elbowYHistory.isNotEmpty) {
      final lastY = _elbowYHistory.last;
      elbowVel = (currElbowY - lastY) / imgH;
    }
    _elbowYHistory.add(currElbowY);
    if (_elbowYHistory.length > _historyMax) _elbowYHistory.removeAt(0);

    // History for ROM/consistency
    _elbowAngleHistory.add(elbowAng);
    if (_elbowAngleHistory.length > _historyMax) _elbowAngleHistory.removeAt(0);

    // 5) Wrist height (0..1)
    final wristHeight = wristR.y / imgH;

    // 6) Movement consistency (0..1)
    double movementConsistency = 0.5;
    if (_elbowAngleHistory.length >= 3) {
      final mean =
          _elbowAngleHistory.reduce((a, b) => a + b) /
          _elbowAngleHistory.length;
      double variance = 0;
      for (final v in _elbowAngleHistory) {
        variance += (v - mean) * (v - mean);
      }
      variance /= _elbowAngleHistory.length;
      movementConsistency = 1.0 / (1.0 + variance);
    }

    // 7) ROM (0..1)
    double rom = 0.0;
    if (_elbowAngleHistory.isNotEmpty) {
      final maxA = _elbowAngleHistory.reduce(math.max);
      final minA = _elbowAngleHistory.reduce(math.min);
      rom = (maxA - minA) / 180.0;
    }

    final features = <double>[
      elbowAng,
      elbowDx,
      torsoIncl,
      elbowVel,
      wristHeight,
      movementConsistency,
      rom,
    ];

    final prediction = await _runOnnx(features);
    _feedback = prediction;
  }

  Future<String> _runOnnx(List<double> features) async {
    final session = _session;
    if (session == null) return 'Model not ready';
    if (_labels.isEmpty) return 'Loading labels...';

    OrtValueTensor? input;
    List<OrtValue?> outputs = const [];
    try {
      input = OrtValueTensor.createTensorWithDataList(
        Float32List.fromList(features),
        [1, features.length],
      );

      // Adjust input name if needed (e.g., 'input', 'input_0')
      outputs = session.run(OrtRunOptions(), {'X': input});
      if (outputs.isEmpty) return 'No output';

      final raw = outputs.first?.value; // null-safe access
      if (raw == null) return 'No output value';

      // Case: probs [[p1, p2, ...]]
      if (raw is List && raw.isNotEmpty && raw.first is List) {
        final probs = List<double>.from(
          (raw.first as List).map((e) => (e as num).toDouble()),
        );
        final maxVal = probs.reduce(math.max);
        final maxIdx = probs.indexOf(maxVal);
        return _labels[maxIdx.clamp(0, _labels.length - 1)];
      }

      // Case: [idx] or [0,1,0,...]
      if (raw is List && raw.isNotEmpty) {
        final first = raw.first;
        int idx;
        if (first is int) {
          idx = first;
        } else if (first is double) {
          idx = first.toInt();
        } else {
          return 'Invalid output';
        }
        return _labels[idx.clamp(0, _labels.length - 1)];
      }

      return 'Unknown';
    } catch (e) {
      if (kDebugMode) debugPrint('[ONNX] Inference error: $e');
      return 'Inference error';
    } finally {
      // Release native resources
      try {
        input?.release();
      } catch (_) {}
      for (final o in outputs) {
        try {
          o?.release();
        } catch (_) {}
      }
    }
  }

  void _showInstructionsDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (_) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.fitness_center, color: Colors.indigo, size: 26),
                SizedBox(width: 8),
                Text(
                  'Bicep Curl',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            content: const SingleChildScrollView(
              child: Text(
                '1) Face the camera and perform bicep curls\n'
                '2) Keep your upper arms still\n'
                '3) Avoid swinging or leaning\n\n'
                'The model will classify your form in real-time.',
                style: TextStyle(fontSize: 14, height: 1.5),
              ),
            ),
            actions: [
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Start'),
              ),
            ],
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hudColor = _feedback == 'good' ? Colors.green : Colors.orangeAccent;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bicep Curl'),
        backgroundColor: Colors.black.withValues(alpha: 0.7),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: _showInstructionsDialog,
          ),
        ],
      ),
      body:
          _showCamera
              ? Stack(
                children: [
                  CameraWidget(
                    showCamera: _showCamera,
                    onImage: _onCameraImage,
                    // Lower resolution + drop frames at source to reduce lag
                    resolution: ResolutionPreset.low,
                    imageFormat:
                        Platform.isIOS
                            ? ImageFormatGroup.bgra8888
                            : ImageFormatGroup.yuv420,
                    maxFps: 12, // 10–15 recommended with ONNX
                  ),
                  Positioned(
                    top: 16,
                    left: 16,
                    right: 16,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        border: Border.all(color: hudColor, width: 2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: DefaultTextStyle(
                        style: const TextStyle(color: Colors.white),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Form: $_feedback',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Labels: good, half_rep, lean, swing',
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              )
              : const Center(child: Text('Camera off')),
    );
  }
}
