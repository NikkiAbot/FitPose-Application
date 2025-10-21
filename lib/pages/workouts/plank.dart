import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:onnxruntime/onnxruntime.dart';
import '../../../components/camera_widget.dart';

class Plank extends StatefulWidget {
  const Plank({super.key});

  @override
  State<Plank> createState() => _PlankState();
}

class _PlankState extends State<Plank> {
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
  String _feedback = 'Get into plank position';
  Duration _holdTime = Duration.zero;
  Timer? _timer;
  bool _holding = false;

  InputImageRotation _rotation = InputImageRotation.rotation0deg;
  OrtSession? _onnxSession;

  @override
  void initState() {
    super.initState();
    // Lock to landscape mode
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
    _timer?.cancel();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    super.dispose();
  }

  Future<void> _loadOnnxModel() async {
    try {
      OrtEnv.instance.init();
      final bytes =
          (await rootBundle.load(
            'assets/onnx/plank_model.onnx',
          )).buffer.asUint8List();
      final options = OrtSessionOptions();
      _onnxSession = OrtSession.fromBuffer(bytes, options);
      if (kDebugMode) print('[ONNX] Model loaded.');
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
        _stopTimer();
        return;
      }

      _latestPose = poses.first;
      _analyzePose(_latestPose!);

      // ONNX inference after pose analysis
      await _analyzeWithOnnx(_latestPose!);
    } catch (e) {
      if (kDebugMode) print('[Plank] Exception: $e');
      _latestPose = null;
      _feedback = 'Error processing frame';
      _goodForm = false;
      _stopTimer();
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

  void _analyzePose(Pose pose) {
    final lm = pose.landmarks;

    // Choose the better visible side
    final lS = lm[PoseLandmarkType.leftShoulder];
    final lH = lm[PoseLandmarkType.leftHip];
    final lA = lm[PoseLandmarkType.leftAnkle];

    final rS = lm[PoseLandmarkType.rightShoulder];
    final rH = lm[PoseLandmarkType.rightHip];
    final rA = lm[PoseLandmarkType.rightAnkle];

    final leftScore =
        (lS?.likelihood ?? 0) + (lH?.likelihood ?? 0) + (lA?.likelihood ?? 0);
    final rightScore =
        (rS?.likelihood ?? 0) + (rH?.likelihood ?? 0) + (rA?.likelihood ?? 0);
    final useLeft = leftScore >= rightScore;

    final s = useLeft ? lS : rS;
    final h = useLeft ? lH : rH;
    final a = useLeft ? lA : rA;

    if (s == null || h == null || a == null) {
      _feedback = 'Make sure your side body is fully visible';
      _goodForm = false;
      _stopTimer(reset: true);
      return;
    }

    final S = Offset(s.x, s.y);
    final H = Offset(h.x, h.y);
    final A = Offset(a.x, a.y);

    // Subject size check (scale-invariant)
    final saLen = (S - A).distance;
    final imgMin = math.min(
      (_imageWidth ?? 0).toDouble(),
      (_imageHeight ?? 0).toDouble(),
    );
    if (imgMin > 0 && saLen < imgMin * 0.25) {
      _feedback = 'Move closer to the camera';
      _goodForm = false;
      _stopTimer(reset: true);
      return;
    }

    // Side-on check: shoulder separation should be small vs body length
    if (lS != null && rS != null) {
      final shoulderSep = (Offset(lS.x, lS.y) - Offset(rS.x, rS.y)).distance;
      final ratio = shoulderSep / (saLen + 1e-6);
      if (ratio > 0.5) {
        _feedback = 'Turn your side to the camera';
        _goodForm = false;
        _stopTimer(reset: true);
        return;
      }
    }

    // Hip straightness (angle at hip)
    double angle(Offset a, Offset b, Offset c) {
      final ab = a - b;
      final cb = c - b;
      double rad = math.atan2(cb.dy, cb.dx) - math.atan2(ab.dy, ab.dx);
      double deg = (rad * 180.0 / math.pi).abs();
      if (deg > 180.0) deg = 360 - deg;
      return deg;
    }

    final bodyAngle = angle(S, H, A);

    // Signed hip deviation from shoulder–ankle line (pixels)
    double hipDev(Offset s, Offset h, Offset a) {
      final sa = a - s;
      final sh = h - s;
      final denom = (sa.dx * sa.dx + sa.dy * sa.dy).clamp(
        1e-6,
        double.infinity,
      );
      final t = (sh.dx * sa.dx + sh.dy * sa.dy) / denom;
      final p = Offset(s.dx + sa.dx * t, s.dy + sa.dy * t);
      return h.dy - p.dy; // +: hips too low (sag), -: hips too high (pike)
    }

    final dev = hipDev(S, H, A);
    final devThr = saLen * 0.05;

    // Orientation of shoulder–ankle vs expected axis given image rotation
    double segAngle =
        (math.atan2(A.dy - S.dy, A.dx - S.dx) * 180 / math.pi).abs();
    if (segAngle > 180) segAngle -= 180; // [0,180]
    final expectVertical =
        _rotation == InputImageRotation.rotation90deg ||
        _rotation == InputImageRotation.rotation270deg;
    final deltaToVertical = (segAngle - 90).abs();
    final deltaToHorizontal = math.min(segAngle, 180 - segAngle);
    final orientationOk =
        expectVertical ? (deltaToVertical <= 15) : (deltaToHorizontal <= 15);

    final straightOk = bodyAngle >= 170 && bodyAngle <= 190;
    final devOk = dev.abs() <= devThr;

    if (orientationOk && straightOk && devOk) {
      _feedback = 'Good plank!';
      _goodForm = true;
      _startTimer();
    } else {
      if (!orientationOk) {
        _feedback = 'Align body parallel to the floor';
      } else if (dev > devThr) {
        _feedback = 'Hips too low';
      } else if (dev < -devThr) {
        _feedback = 'Hips too high';
      } else {
        _feedback = 'Straighten your body';
      }
      _goodForm = false;
      _stopTimer();
    }
  }

  Future<void> _analyzeWithOnnx(Pose pose) async {
    if (_onnxSession == null) return;
    try {
      final landmarks = pose.landmarks;
      final inputData = <double>[];

      // 17 keypoints (x, y normalized)
      final keypoints = [
        PoseLandmarkType.nose,
        PoseLandmarkType.leftEye,
        PoseLandmarkType.rightEye,
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
        PoseLandmarkType.leftEar,
        PoseLandmarkType.rightEar,
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
        final output = outputs.first;
        if (output is OrtValueTensor) {
          final List<double> outputValue = List<double>.from(output.value);
          if (outputValue.isNotEmpty) {
            final maxVal = outputValue.reduce(math.max);
            final resultClass = outputValue.indexOf(maxVal);
            switch (resultClass) {
              case 0:
                _feedback = 'Hips too low (AI detected)';
                _goodForm = false;
                _stopTimer();
                break;
              case 1:
                _feedback = 'Hips too high (AI detected)';
                _goodForm = false;
                _stopTimer();
                break;
              case 2:
                _feedback = 'Good plank (AI verified)';
                _goodForm = true;
                _startTimer();
                break;
              default:
                _feedback = 'Unknown AI output';
                _goodForm = false;
                _stopTimer();
            }
          } else {
            _feedback = 'Model output empty';
          }
        } else {
          _feedback = 'Invalid model output';
        }
      } else {
        _feedback = 'No model output';
      }

      for (final o in outputs) {
        o?.release();
      }
    } catch (e) {
      if (kDebugMode) print('[ONNX] Inference failed: $e');
    }
  }

  void _startTimer() {
    if (_holding) return;
    _holding = true;
    _timer ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (_holding) {
        setState(() => _holdTime += const Duration(seconds: 1));
      }
    });
  }

  void _stopTimer({bool reset = false}) {
    if (!_holding) {
      if (reset) setState(() => _holdTime = Duration.zero);
      return;
    }
    _holding = false;
    if (reset) setState(() => _holdTime = Duration.zero);
  }

  String get formattedHoldTime {
    final minutes = _holdTime.inMinutes
        .remainder(60)
        .toString()
        .padLeft(2, '0');
    final seconds = _holdTime.inSeconds
        .remainder(60)
        .toString()
        .padLeft(2, '0');
    return '$minutes:$seconds';
  }

  void _showInstructionsDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (_) => AlertDialog(
            title: const Text('Plank Instructions'),
            content: const Text(
              '1) Get into plank position (side view, elbows or hands).\n'
              '2) Keep a straight line from shoulders to heels.\n'
              '3) Ensure the camera sees your full side body.\n'
              '4) The timer runs only when posture is correct.',
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
          tooltip: 'Back',
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
                        painter: _PlankPainter(
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
                              'Hold Time: $formattedHoldTime',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
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

class _PlankPainter extends CustomPainter {
  final Pose pose;
  final int imageWidth;
  final int imageHeight;
  final bool postureGood;
  final InputImageRotation rotation;

  _PlankPainter({
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

    final connections = [
      [PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder],
      [PoseLandmarkType.leftHip, PoseLandmarkType.rightHip],
      [PoseLandmarkType.leftShoulder, PoseLandmarkType.leftHip],
      [PoseLandmarkType.rightShoulder, PoseLandmarkType.rightHip],
      [PoseLandmarkType.leftHip, PoseLandmarkType.leftKnee],
      [PoseLandmarkType.rightHip, PoseLandmarkType.rightKnee],
      [PoseLandmarkType.leftKnee, PoseLandmarkType.leftAnkle],
      [PoseLandmarkType.rightKnee, PoseLandmarkType.rightAnkle],
    ];

    final linePaint =
        Paint()
          ..color = Colors.white
          ..strokeWidth = 2;
    final jointPaint =
        Paint()..color = postureGood ? Colors.greenAccent : Colors.redAccent;

    for (final pair in connections) {
      final a = lm[pair[0]];
      final b = lm[pair[1]];
      if (a == null || b == null) continue;
      canvas.drawLine(map(a.x, a.y), map(b.x, b.y), linePaint);
    }

    for (final l in lm.values) {
      canvas.drawCircle(map(l.x, l.y), 5, jointPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _PlankPainter old) =>
      old.pose != pose || old.postureGood != postureGood;
}
