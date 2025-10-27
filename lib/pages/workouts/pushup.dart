import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:onnxruntime/onnxruntime.dart';
import '../../../components/camera_widget.dart';

class PushUp extends StatefulWidget {
  const PushUp({super.key});

  @override
  State<PushUp> createState() => _PushUpState();
}

class _PushUpState extends State<PushUp> {
  final _showCamera = true;
  late final PoseDetector _poseDetector = PoseDetector(
    options: PoseDetectorOptions(mode: PoseDetectionMode.stream),
  );

  bool _isProcessing = false;
  int _lastProcessMs = 0;
  Pose? _latestPose;
  int? _imageWidth;
  int? _imageHeight;

  bool _goodForm = false;
  String _feedback = 'Get into push-up position';
  int _pushUpCount = 0;
  bool _downPosition = false;

  String _elbowAngleDisplay = '-';
  String _torsoAngleDisplay = '-';
  String _verticalMovementDisplay = '-';

  double _previousHipY = 0.0;
  double _movementDelta = 0.0;

  InputImageRotation _rotation = InputImageRotation.rotation0deg;
  OrtSession? _onnxSession;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _showInstructionsDialog(),
    );
    _loadOnnxModel();
  }

  @override
  void dispose() {
    _poseDetector.close();
    _onnxSession?.release();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    });
    super.dispose();
  }

  Future<void> _loadOnnxModel() async {
    try {
      OrtEnv.instance.init();
      final bytes =
          (await rootBundle.load(
            'assets/onnx/push_up_model.onnx',
          )).buffer.asUint8List();
      final options = OrtSessionOptions();
      _onnxSession = OrtSession.fromBuffer(bytes, options);
      if (kDebugMode) print('[ONNX] Push-up model loaded.');
    } catch (e) {
      if (kDebugMode) print('[ONNX] Model load failed: $e');
    }
  }

  void _onCameraImage(
    CameraImage image,
    int rotationDegrees,
    bool isFrontCamera,
  ) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_isProcessing || now - _lastProcessMs < 150) return;
    _isProcessing = true;
    _lastProcessMs = now;
    _rotation = _rotationFromDegrees(rotationDegrees);

    _processPose(image).whenComplete(() {
      _isProcessing = false;
      if (mounted) setState(() {});
    });
  }

  InputImageRotation _rotationFromDegrees(int degrees) {
    switch (degrees) {
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
      final nv21 = _yuv420ToNv21(image);

      final inputImage = InputImage.fromBytes(
        bytes: nv21,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: _rotation,
          format: InputImageFormat.nv21,
          bytesPerRow: image.planes.first.bytesPerRow,
        ),
      );

      final poses = await _poseDetector.processImage(inputImage);
      if (poses.isEmpty) {
        _latestPose = null;
        _feedback = 'No person detected';
        _goodForm = false;
        return;
      }

      _latestPose = poses.first;
      _analyzePushUpPose(_latestPose!);
      await _analyzeWithOnnx(_latestPose!);
    } catch (e) {
      if (kDebugMode) print('[PushUp] Exception: $e');
      _feedback = 'Error processing frame';
      _goodForm = false;
    }
  }

  Uint8List _yuv420ToNv21(CameraImage image) {
    final width = image.width;
    final height = image.height;
    final ySize = width * height;
    final chromaWidth = width ~/ 2;
    final chromaHeight = height ~/ 2;
    final chromaSize = chromaWidth * chromaHeight;
    final out = Uint8List(ySize + 2 * chromaSize);

    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];

    int outIndex = 0;
    for (int row = 0; row < height; row++) {
      out.setRange(
        outIndex,
        outIndex + width,
        yPlane.bytes,
        row * yPlane.bytesPerRow,
      );
      outIndex += width;
    }

    int chromaOut = ySize;
    for (int row = 0; row < chromaHeight; row++) {
      for (int col = 0; col < chromaWidth; col++) {
        final uIndex =
            row * uPlane.bytesPerRow + col * (uPlane.bytesPerPixel ?? 1);
        final vIndex =
            row * vPlane.bytesPerRow + col * (vPlane.bytesPerPixel ?? 1);
        out[chromaOut++] = vPlane.bytes[vIndex];
        out[chromaOut++] = uPlane.bytes[uIndex];
      }
    }
    return out;
  }

  void _analyzePushUpPose(Pose pose) {
    final lm = pose.landmarks;
    final s = lm[PoseLandmarkType.rightShoulder];
    final e = lm[PoseLandmarkType.rightElbow];
    final w = lm[PoseLandmarkType.rightWrist];
    final h = lm[PoseLandmarkType.rightHip];
    final a = lm[PoseLandmarkType.rightAnkle];

    if (s == null || e == null || w == null || h == null || a == null) {
      _feedback = 'Make sure your full body is visible';
      _goodForm = false;
      return;
    }

    double angle(Offset a, Offset b, Offset c) {
      final ab = a - b;
      final cb = c - b;
      double rad = math.atan2(cb.dy, cb.dx) - math.atan2(ab.dy, ab.dx);
      double deg = (rad * 180.0 / math.pi).abs();
      if (deg > 180.0) deg = 360 - deg;
      return deg;
    }

    final elbowAngle = angle(
      Offset(s.x, s.y),
      Offset(e.x, e.y),
      Offset(w.x, w.y),
    );
    final torsoAngle = angle(
      Offset(s.x, s.y),
      Offset(h.x, h.y),
      Offset(a.x, a.y),
    );

    // ✅ Detect vertical motion using hip movement (Y axis)
    final currentHipY = h.y;
    _movementDelta = (_previousHipY - currentHipY).abs();
    _previousHipY = currentHipY;

    final torsoAligned = torsoAngle > 150;

    // Thresholds
    const double verticalThresholdDown =
        0.04; // amount of downward motion to trigger "down"
    const double verticalThresholdUp = 0.02;

    if (_movementDelta > verticalThresholdDown &&
        elbowAngle < 80 &&
        torsoAligned) {
      _downPosition = true;
      _feedback = 'Going down...';
      _goodForm = true;
    } else if (_movementDelta > verticalThresholdUp &&
        elbowAngle > 150 &&
        _downPosition &&
        torsoAligned) {
      _pushUpCount++;
      _downPosition = false;
      _feedback = 'Push-up complete ✅';
      _goodForm = true;
    } else {
      _feedback = torsoAligned ? 'Lower your body' : 'Keep your body straight';
      _goodForm = false;
    }

    _elbowAngleDisplay = elbowAngle.toStringAsFixed(1);
    _torsoAngleDisplay = torsoAngle.toStringAsFixed(1);
    _verticalMovementDisplay = _movementDelta.toStringAsFixed(3);
  }

  Future<void> _analyzeWithOnnx(Pose pose) async {
    if (_onnxSession == null) return;
    try {
      final landmarks = pose.landmarks;
      final inputData = <double>[];

      final keypoints = [
        PoseLandmarkType.nose,
        PoseLandmarkType.leftShoulder,
        PoseLandmarkType.rightShoulder,
        PoseLandmarkType.leftElbow,
        PoseLandmarkType.rightElbow,
        PoseLandmarkType.leftWrist,
        PoseLandmarkType.rightWrist,
        PoseLandmarkType.leftHip,
        PoseLandmarkType.rightHip,
        PoseLandmarkType.leftKnee,
        PoseLandmarkType.rightKnee,
        PoseLandmarkType.leftAnkle,
        PoseLandmarkType.rightAnkle,
      ];

      for (final type in keypoints) {
        final lm = landmarks[type];
        inputData.add((lm?.x ?? 0) / (_imageWidth ?? 1));
        inputData.add((lm?.y ?? 0) / (_imageHeight ?? 1));
      }

      final inputTensor = OrtValueTensor.createTensorWithDataList(
        Float32List.fromList(inputData),
        [1, inputData.length],
      );

      final inputs = {_onnxSession!.inputNames.first: inputTensor};
      final outputs = _onnxSession!.run(OrtRunOptions(), inputs);

      inputTensor.release();

      if (outputs.isNotEmpty) {
        final outputTensor = outputs.first;
        if (outputTensor is OrtValueTensor) {
          final data = outputTensor.value;
          final outputValue =
              data is Float32List ? data.toList() : List<double>.from(data);
          if (outputValue.isNotEmpty) {
            final maxVal = outputValue.reduce(math.max);
            final resultClass = outputValue.indexOf(maxVal);
            switch (resultClass) {
              case 0:
                _feedback = 'Body too low (AI detected)';
                _goodForm = false;
                break;
              case 1:
                _feedback = 'Hips too high (AI detected)';
                _goodForm = false;
                break;
              case 2:
                _feedback = 'Good push-up (AI verified)';
                _goodForm = true;
                break;
            }
          }
        }
      }

      for (final o in outputs) {
        o?.release();
      }
    } catch (e) {
      if (kDebugMode) print('[ONNX PushUp] Inference failed: $e');
    }
  }

  void _showInstructionsDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (_) => AlertDialog(
            title: const Text('Push-Up Instructions'),
            content: const Text(
              '1️⃣ Get into push-up position (side view).\n'
              '2️⃣ Lower your body vertically until elbows are bent (~70°).\n'
              '3️⃣ Push back up until arms are straight (~150°).\n'
              '4️⃣ Keep your body straight from shoulders to ankles.\n'
              '5️⃣ Camera should capture full body side profile.',
            ),
            actions: [
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.purple),
                child: const Text('Start'),
              ),
            ],
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hudColor = _goodForm ? Colors.green : Colors.redAccent;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.grey, size: 28),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body:
          _showCamera
              ? Stack(
                children: [
                  CameraWidget(
                    showCamera: _showCamera,
                    onImage: _onCameraImage,
                  ),
                  if (_latestPose != null &&
                      _imageWidth != null &&
                      _imageHeight != null)
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _PushUpPainter(
                          pose: _latestPose!,
                          imageWidth: _imageWidth!,
                          imageHeight: _imageHeight!,
                          postureGood: _goodForm,
                          rotation: _rotation,
                        ),
                      ),
                    ),
                  Positioned(
                    bottom: 16,
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
                              'Push-Ups: $_pushUpCount',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text('Right Elbow Angle: $_elbowAngleDisplay°'),
                            Text('Torso Angle: $_torsoAngleDisplay°'),
                            Text(
                              'Vertical Movement: $_verticalMovementDisplay',
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _feedback,
                              style: TextStyle(
                                color:
                                    _goodForm
                                        ? Colors.greenAccent
                                        : Colors.orangeAccent,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              )
              : const Center(
                child: Text(
                  'Camera off',
                  style: TextStyle(color: Colors.white),
                ),
              ),
    );
  }
}

class _PushUpPainter extends CustomPainter {
  final Pose pose;
  final int imageWidth;
  final int imageHeight;
  final bool postureGood;
  final InputImageRotation rotation;

  _PushUpPainter({
    required this.pose,
    required this.imageWidth,
    required this.imageHeight,
    required this.postureGood,
    required this.rotation,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final lm = pose.landmarks;
    final previewSize = Size(imageWidth.toDouble(), imageHeight.toDouble());

    Offset map(double x, double y) {
      final scale = math.max(
        size.width / previewSize.width,
        size.height / previewSize.height,
      );
      final scaledW = previewSize.width * scale;
      final scaledH = previewSize.height * scale;
      final offsetX = (size.width - scaledW) / 2;
      final offsetY = (size.height - scaledH) / 2;

      double px = x * scale;
      double py = y * scale;

      // Mirror horizontally if front camera or rotation applied
      switch (rotation) {
        case InputImageRotation.rotation90deg:
          final tmpX = px;
          px = scaledW - py;
          py = tmpX;
          break;
        case InputImageRotation.rotation270deg:
          final tmpX = px;
          px = py;
          py = scaledH - tmpX;
          break;
        case InputImageRotation.rotation180deg:
          px = scaledW - px;
          py = scaledH - py;
          break;
        default:
          px = scaledW - px;
          break;
      }

      final mappedX = px + offsetX;
      final mappedY = py + offsetY;
      return Offset(mappedX, size.height - mappedY);
    }

    final linePaint =
        Paint()
          ..color = Colors.white
          ..strokeWidth = 3;
    final jointPaint =
        Paint()..color = postureGood ? Colors.greenAccent : Colors.redAccent;

    // ✅ Define a right-side chain: shoulder → elbow → wrist → hip → knee → ankle
    final chain = [
      PoseLandmarkType.rightShoulder,
      PoseLandmarkType.rightElbow,
      PoseLandmarkType.rightWrist,
      PoseLandmarkType.rightHip,
      PoseLandmarkType.rightKnee,
      PoseLandmarkType.rightAnkle,
    ];

    // Draw skeleton chain
    for (int i = 0; i < chain.length - 1; i++) {
      final a = lm[chain[i]];
      final b = lm[chain[i + 1]];
      if (a != null && b != null) {
        canvas.drawLine(map(a.x, a.y), map(b.x, b.y), linePaint);
      }
    }

    // Draw each landmark as a small circle
    for (final type in chain) {
      final l = lm[type];
      if (l != null) {
        canvas.drawCircle(map(l.x, l.y), 5, jointPaint);
      }
    }

    // Optional: draw head indicator for orientation
    final head = lm[PoseLandmarkType.nose];
    if (head != null) {
      final headPaint =
          Paint()
            ..color = Colors.blueAccent
            ..style = PaintingStyle.fill;
      canvas.drawCircle(map(head.x, head.y), 5, headPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _PushUpPainter old) =>
      old.pose != pose || old.postureGood != postureGood;
}
