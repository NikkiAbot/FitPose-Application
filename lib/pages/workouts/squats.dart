import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:flutter/services.dart';
import 'package:onnxruntime/onnxruntime.dart';

import '../../../components/camera_widget.dart';

class Squats extends StatefulWidget {
  const Squats({super.key});

  @override
  State<Squats> createState() => _SquatsState();
}

class _SquatsState extends State<Squats> {
  final _showCamera = true;

  late final PoseDetector _poseDetector = PoseDetector(
    options: PoseDetectorOptions(mode: PoseDetectionMode.stream),
  );

  OrtSession? _onnxSession;

  bool _isProcessing = false;
  int _lastProcessMs = 0;

  Pose? _latestPose;
  int? _imageWidth;
  int? _imageHeight;

  // Metrics
  double? _leftKnee;
  double? _rightKnee;
  double? _avgKnee;
  double? _torsoAngle;
  String _feedback = 'Face the camera and stand tall';
  String _postureStatus = 'Tracking...';
  bool _postureGood = false;

  // FSM
  int _reps = 0;
  String _state = 'waiting'; // waiting | down | up
  bool _anomaly = false;

  // Thresholds
  static const double downThresh = 90;
  static const double upThresh = 160;
  static const double maxTorsoLeanDeg = 20;
  static const double maxAsymmetryDeg = 15;

  InputImageRotation _rotation = InputImageRotation.rotation270deg;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _showInstructionsDialog(),
    );
    _loadOnnxModel();
  }

  @override
  void dispose() {
    _poseDetector.close();
    _onnxSession?.release();
    super.dispose();
  }

  Future<void> _loadOnnxModel() async {
    try {
      OrtEnv.instance.init();
      final bytes =
          (await rootBundle.load(
            'assets/onnx/squats_model.onnx',
          )).buffer.asUint8List();
      final options = OrtSessionOptions();
      _onnxSession = OrtSession.fromBuffer(bytes, options);
    } catch (e) {
      if (kDebugMode) print('[ONNX] Failed to load model: $e');
    }
  }

  void _onCameraImage(
    CameraImage image,
    int rotationDegrees,
    bool isFrontCamera,
  ) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_isProcessing || now - _lastProcessMs < 120) return;
    _isProcessing = true;
    _lastProcessMs = now;

    _rotation = InputImageRotation.rotation270deg;

    _processPose(image).whenComplete(() {
      _isProcessing = false;
      if (mounted) setState(() {});
    });
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
        _feedback = 'No pose detected';
        _postureStatus = 'Tracking...';
        _postureGood = false;
        return;
      }

      _latestPose = poses.first;

      // --- Run rule-based analysis ---
      _analyzePose(_latestPose!);

      // --- Run ONNX model ---
      await _analyzeWithOnnx(_latestPose!);
    } catch (e) {
      if (kDebugMode) print('[Squats] Exception: $e');
      _latestPose = null;
      _feedback = 'Error processing frame';
      _postureStatus = 'Tracking...';
      _postureGood = false;
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

  double _angle(Offset a, Offset b, Offset c) {
    a = Offset(a.dx, -a.dy);
    b = Offset(b.dx, -b.dy);
    c = Offset(c.dx, -c.dy);
    final ab = a - b;
    final cb = c - b;
    final dot = ab.dx * cb.dx + ab.dy * cb.dy;
    final denom = ab.distance * cb.distance;
    if (denom == 0) return 0;
    final cosv = (dot / denom).clamp(-1.0, 1.0);
    return (180 / math.pi) * math.acos(cosv);
  }

  void _analyzePose(Pose pose) {
    final lm = pose.landmarks;

    final lh = lm[PoseLandmarkType.leftHip];
    final rh = lm[PoseLandmarkType.rightHip];
    final lk = lm[PoseLandmarkType.leftKnee];
    final rk = lm[PoseLandmarkType.rightKnee];
    final la = lm[PoseLandmarkType.leftAnkle];
    final ra = lm[PoseLandmarkType.rightAnkle];
    final ls = lm[PoseLandmarkType.leftShoulder];
    final rs = lm[PoseLandmarkType.rightShoulder];

    if ([lh, rh, lk, rk, la, ra, ls, rs].any((p) => p == null)) {
      _feedback = 'Move fully into view';
      _postureStatus = 'Tracking...';
      _postureGood = false;
      return;
    }

    _leftKnee = _angle(
      Offset(lh!.x, lh.y),
      Offset(lk!.x, lk.y),
      Offset(la!.x, la.y),
    );
    _rightKnee = _angle(
      Offset(rh!.x, rh.y),
      Offset(rk!.x, rk.y),
      Offset(ra!.x, ra.y),
    );
    _avgKnee = ((_leftKnee ?? 0) + (_rightKnee ?? 0)) / 2.0;

    final midSh = Offset((ls!.x + rs!.x) / 2, (ls.y + rs.y) / 2);
    final midHp = Offset((lh.x + rh.x) / 2, (lh.y + rh.y) / 2);
    final torsoVec = midSh - midHp;
    _torsoAngle =
        (180 / math.pi) * math.atan2(torsoVec.dx.abs(), torsoVec.dy.abs());

    final kneesDiff = ((_leftKnee ?? 0) - (_rightKnee ?? 0)).abs();
    final upright = _torsoAngle! < maxTorsoLeanDeg;
    final symmetric = kneesDiff < maxAsymmetryDeg;
    _postureGood = upright && symmetric;
    _postureStatus =
        _postureGood
            ? 'Good posture'
            : (!upright ? 'Keep chest up' : 'Balance knees evenly');

    // FSM for rep counting
    if (_state == 'waiting') {
      if (_avgKnee! < downThresh) {
        _state = 'down';
        _anomaly = false;
      }
    } else if (_state == 'down') {
      if (_avgKnee! > upThresh) {
        _state = 'up';
        if (!_postureGood) _anomaly = true;
      }
    } else if (_state == 'up') {
      if (_avgKnee! < downThresh) {
        if (!_anomaly && _postureGood) {
          _reps += 1;
          _feedback = 'Rep ✓';
        } else {
          _feedback = 'Fix form for clean rep';
        }
        _state = 'down';
        _anomaly = false;
      }
    }
  }

  Future<void> _analyzeWithOnnx(Pose pose) async {
    if (_onnxSession == null || _imageWidth == null || _imageHeight == null) {
      return;
    }

    final keyJoints = [
      PoseLandmarkType.leftShoulder,
      PoseLandmarkType.rightShoulder,
      PoseLandmarkType.leftHip,
      PoseLandmarkType.rightHip,
      PoseLandmarkType.leftKnee,
      PoseLandmarkType.rightKnee,
      PoseLandmarkType.leftAnkle,
      PoseLandmarkType.rightAnkle,
    ];

    final features = <double>[];
    final width = _imageWidth!;
    final height = _imageHeight!;

    for (final jt in keyJoints) {
      final lm = pose.landmarks[jt];
      features.add((lm?.x ?? 0.0) / width);
      features.add((lm?.y ?? 0.0) / height);
    }

    final inputTensor = OrtValueTensor.createTensorWithDataList(
      Float32List.fromList(features),
      [1, features.length],
    );

    try {
      final outputs = _onnxSession!.run(OrtRunOptions(), {
        'float_input': inputTensor,
      });
      if (outputs.isEmpty) return;

      final floatData = outputs.first?.toFloat32List();
      if (floatData == null || floatData.length < 2) return;

      final modelScore = floatData[0];
      final repDetected = floatData[1] > 0.5;

      // Combine ONNX output with rule-based posture
      _postureGood = _postureGood && modelScore > 0.7;
      if (repDetected && !_anomaly && _postureGood) _reps += 1;
      _feedback = _postureGood ? 'Good form' : 'Fix form';
    } catch (e) {
      if (kDebugMode) print('[ONNX] Inference failed: $e');
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
                Icon(Icons.directions_run, color: Colors.purple, size: 26),
                SizedBox(width: 8),
                Text(
                  'Squats',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            content: const SingleChildScrollView(
              child: Text(
                '1) Stand with feet shoulder-width apart\n'
                '2) Keep your chest up and core tight\n'
                '3) Lower until thighs are parallel to the floor\n'
                '4) Push up through your heels\n'
                '5) Keep knees tracking over toes\n\n'
                'Camera will track your reps and posture.',
                style: TextStyle(fontSize: 14, height: 1.5),
              ),
            ),
            actions: [
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purple,
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
    final hudColor = _postureGood ? Colors.green : Colors.redAccent;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Squats'),
        backgroundColor: Colors.black.withAlpha(180),
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
                  ),
                  if (_latestPose != null &&
                      _imageWidth != null &&
                      _imageHeight != null)
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _SquatsPainter(
                          pose: _latestPose!,
                          imageWidth: _imageWidth!,
                          imageHeight: _imageHeight!,
                          leftKnee: _leftKnee,
                          rightKnee: _rightKnee,
                          avgKnee: _avgKnee,
                          torsoAngle: _torsoAngle,
                          postureGood: _postureGood,
                          rotation: _rotation,
                          mirror: false,
                        ),
                      ),
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
                              'State: $_state   Reps: $_reps',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (_avgKnee != null)
                              Text(
                                'Avg Knee: ${_avgKnee!.toStringAsFixed(0)}°',
                              ),
                            if (_leftKnee != null && _rightKnee != null)
                              Text(
                                'L/R Knee: ${_leftKnee!.toStringAsFixed(0)}° / ${_rightKnee!.toStringAsFixed(0)}°',
                              ),
                            if (_torsoAngle != null)
                              Text(
                                'Torso: ${_torsoAngle!.toStringAsFixed(0)}°',
                              ),
                            Text(
                              _postureStatus,
                              style: TextStyle(
                                color: hudColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _feedback,
                              style: TextStyle(
                                color:
                                    _postureGood
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
              : const Center(child: Text('Camera off')),
    );
  }
}

// === Painter ===
class _SquatsPainter extends CustomPainter {
  final Pose pose;
  final int imageWidth;
  final int imageHeight;
  final double? leftKnee;
  final double? rightKnee;
  final double? avgKnee;
  final double? torsoAngle;
  final bool postureGood;
  final InputImageRotation rotation;
  final bool mirror;

  _SquatsPainter({
    required this.pose,
    required this.imageWidth,
    required this.imageHeight,
    required this.leftKnee,
    required this.rightKnee,
    required this.avgKnee,
    required this.torsoAngle,
    required this.postureGood,
    required this.rotation,
    required this.mirror,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final lm = pose.landmarks;

    final rotated =
        rotation == InputImageRotation.rotation90deg ||
        rotation == InputImageRotation.rotation270deg;
    final effW = rotated ? imageHeight : imageWidth;
    final effH = rotated ? imageWidth : imageHeight;
    final scaleX = size.width / effW;
    final scaleY = size.height / effH;

    Offset mapPoint(double x, double y) {
      final mappedX = size.width - (x * scaleX);
      final mappedY = y * scaleY;
      return Offset(mappedX, mappedY);
    }

    final connections = [
      [PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder],
      [PoseLandmarkType.leftHip, PoseLandmarkType.rightHip],
      [PoseLandmarkType.leftHip, PoseLandmarkType.leftKnee],
      [PoseLandmarkType.leftKnee, PoseLandmarkType.leftAnkle],
      [PoseLandmarkType.rightHip, PoseLandmarkType.rightKnee],
      [PoseLandmarkType.rightKnee, PoseLandmarkType.rightAnkle],
      [PoseLandmarkType.leftShoulder, PoseLandmarkType.leftHip],
      [PoseLandmarkType.rightShoulder, PoseLandmarkType.rightHip],
    ];

    final linePaint =
        Paint()
          ..color = Colors.white
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round;

    final jointPaint =
        Paint()
          ..color = postureGood ? Colors.greenAccent : Colors.redAccent
          ..style = PaintingStyle.fill;

    for (final pair in connections) {
      final a = lm[pair[0]];
      final b = lm[pair[1]];
      if (a == null || b == null) continue;
      canvas.drawLine(mapPoint(a.x, a.y), mapPoint(b.x, b.y), linePaint);
    }

    for (final l in lm.values) {
      canvas.drawCircle(mapPoint(l.x, l.y), 6, jointPaint);
    }

    void drawLabel(String text, Offset where) {
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: const TextStyle(
            color: Colors.yellowAccent,
            fontSize: 14,
            fontWeight: FontWeight.bold,
            shadows: [Shadow(color: Colors.black, blurRadius: 4)],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, where);
    }

    final lk = lm[PoseLandmarkType.leftKnee];
    final rk = lm[PoseLandmarkType.rightKnee];
    final lh = lm[PoseLandmarkType.leftHip];
    final rh = lm[PoseLandmarkType.rightHip];

    if (leftKnee != null && lk != null) {
      drawLabel(
        '${leftKnee!.toStringAsFixed(0)}°',
        mapPoint(lk.x, lk.y) + const Offset(8, -20),
      );
    }
    if (rightKnee != null && rk != null) {
      drawLabel(
        '${rightKnee!.toStringAsFixed(0)}°',
        mapPoint(rk.x, rk.y) + const Offset(8, -20),
      );
    }
    if (avgKnee != null && lh != null && rh != null) {
      final mid = Offset((lh.x + rh.x) / 2, (lh.y + rh.y) / 2);
      drawLabel(
        'AVG ${avgKnee!.toStringAsFixed(0)}°',
        mapPoint(mid.dx, mid.dy) + const Offset(8, -24),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SquatsPainter old) =>
      old.pose != pose ||
      old.leftKnee != leftKnee ||
      old.rightKnee != rightKnee ||
      old.avgKnee != avgKnee ||
      old.postureGood != postureGood;
}

// --- OrtValue Extension ---
extension OrtValueExtensions on OrtValue {
  Float32List? toFloat32List() {
    if (this is OrtValueTensor) {
      final tensor = this as OrtValueTensor;
      final value = tensor.value;
      if (value is Float32List) {
        return value;
      }
    }
    return null;
  }
}
