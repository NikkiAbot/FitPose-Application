import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import '../../components/camera_widget.dart';

class BicepCurl extends StatefulWidget {
  const BicepCurl({super.key});

  @override
  State<BicepCurl> createState() => _BicepCurlState();
}

class _BicepCurlState extends State<BicepCurl> {
  final _showCamera = true;
  late final PoseDetector _poseDetector = PoseDetector(
    options: PoseDetectorOptions(mode: PoseDetectionMode.stream),
  );

  bool _isProcessing = false;
  int _lastProcessMs = 0;

  Pose? _latestPose;
  int? _imageWidth;
  int? _imageHeight;

  double? _elbowAngle;
  double? _torsoAngle;
  String _feedback = 'Face camera and start';
  String _postureStatus = 'Tracking...';
  bool _postureGood = false;

  int _curlReps = 0;
  bool _inRep = false;
  bool _fullyContracted = false;
  bool _repPostureGood = true;

  static const double extendedAngleThreshold = 160;
  static const double contractedAngleThreshold = 60;
  static const double deepContractAngle = 50;
  static const double maxTorsoLeanDeg = 20;

  InputImageRotation _rotation = InputImageRotation.rotation270deg;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _showInstructionsDialog(),
    );
  }

  @override
  void dispose() {
    _poseDetector.close();
    super.dispose();
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

    // ✅ Lock rotation for portrait orientation (front camera)
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
      _analyzePose(_latestPose!);
    } catch (e) {
      if (kDebugMode) print('[Pose] Exception: $e');
      _latestPose = null;
      _feedback = 'Error processing frame';
      _postureStatus = 'Tracking...';
      _postureGood = false;
    }
  }

  // RULES
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
    final shoulderR = lm[PoseLandmarkType.rightShoulder];
    final elbowR = lm[PoseLandmarkType.rightElbow];
    final wristR = lm[PoseLandmarkType.rightWrist];
    final hipR = lm[PoseLandmarkType.rightHip];
    final shoulderL = lm[PoseLandmarkType.leftShoulder];
    final hipL = lm[PoseLandmarkType.leftHip];

    if (shoulderR == null || elbowR == null || wristR == null || hipR == null) {
      _feedback = 'Move into view';
      _postureStatus = 'Tracking...';
      _postureGood = false;
      return;
    }

    _elbowAngle = _angle(
      Offset(shoulderR.x, shoulderR.y),
      Offset(elbowR.x, elbowR.y),
      Offset(wristR.x, wristR.y),
    );

    if (shoulderL != null && hipL != null) {
      final avgShoulder = Offset(
        (shoulderL.x + shoulderR.x) / 2,
        (shoulderL.y + shoulderR.y) / 2,
      );
      final avgHip = Offset((hipL.x + hipR.x) / 2, (hipL.y + hipR.y) / 2);
      final torsoVec = avgShoulder - avgHip;
      _torsoAngle =
          (180 / math.pi) * math.atan2(torsoVec.dx.abs(), torsoVec.dy.abs());
      _postureGood = _torsoAngle! < maxTorsoLeanDeg;
      _postureStatus = _postureGood ? 'Good Posture' : 'Don’t lean forward';
    }

    (180 - _elbowAngle!).clamp(0, 140);

    if (!_inRep && _elbowAngle! < extendedAngleThreshold - 10) {
      _inRep = true;
      _fullyContracted = false;
      _repPostureGood = _postureGood;
    }

    if (_inRep) {
      _repPostureGood &= _postureGood;

      if (!_fullyContracted && _elbowAngle! <= contractedAngleThreshold) {
        _fullyContracted = true;
      }

      if (_fullyContracted && _elbowAngle! >= extendedAngleThreshold) {
        if (_repPostureGood) {
          _curlReps += 1;
          _feedback = 'Nice curl!';
        } else {
          _feedback = 'Keep torso stable!';
        }
        _inRep = false;
      } else {
        if (_elbowAngle! > 150) {
          _feedback = 'Start curling';
        } else if (_elbowAngle! > 100) {
          _feedback = 'Keep curling';
        } else if (_elbowAngle! > deepContractAngle) {
          _feedback = 'Almost there!';
        } else {
          _feedback = _postureGood ? 'Hold contraction' : 'Don’t swing!';
        }
      }
    } else {
      _feedback = 'Start curling';
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
                '1. Stand straight, hold imaginary dumbbells\n'
                '2. Keep your elbows close to your torso\n'
                '3. Curl your forearm up to shoulder height\n'
                '4. Lower down slowly\n'
                '5. Avoid swinging or leaning\n\n'
                'Camera will guide your reps and form.',
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
    final hudColor = _postureGood ? Colors.green : Colors.redAccent;
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
                  ),
                  if (_latestPose != null &&
                      _imageWidth != null &&
                      _imageHeight != null)
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _BicepCurlPainter(
                          pose: _latestPose!,
                          imageWidth: _imageWidth!,
                          imageHeight: _imageHeight!,
                          elbowAngle: _elbowAngle,
                          torsoAngle: _torsoAngle,
                          postureGood: _postureGood,
                          rotation: _rotation,
                          mirror: true,
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
                              'Reps: $_curlReps',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (_elbowAngle != null)
                              Text(
                                'Elbow: ${_elbowAngle!.toStringAsFixed(0)}°',
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

class _BicepCurlPainter extends CustomPainter {
  final Pose pose;
  final int imageWidth;
  final int imageHeight;
  final double? elbowAngle;
  final double? torsoAngle;
  final bool postureGood;
  final InputImageRotation rotation;
  final bool mirror;

  _BicepCurlPainter({
    required this.pose,
    required this.imageWidth,
    required this.imageHeight,
    required this.elbowAngle,
    required this.torsoAngle,
    required this.postureGood,
    required this.rotation,
    required this.mirror,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();

    final rotated =
        rotation == InputImageRotation.rotation90deg ||
        rotation == InputImageRotation.rotation270deg;
    final effW = rotated ? imageHeight : imageWidth;
    final effH = rotated ? imageWidth : imageHeight;

    // ✅ Scale calculations
    final scaleX = size.width / effW;
    final scaleY = size.height / effH;

    // ✅ Correct mapping: no mirror on X, flip Y vertically
    Offset mapPoint(double x, double y) {
      final newX = size.width - (x * scaleX);
      final newY = y * scaleY;
      return Offset(newX, newY);
    }

    final lm = pose.landmarks;

    final connections = [
      [PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder],
      [PoseLandmarkType.leftHip, PoseLandmarkType.rightHip],
      [PoseLandmarkType.leftShoulder, PoseLandmarkType.leftElbow],
      [PoseLandmarkType.leftElbow, PoseLandmarkType.leftWrist],
      [PoseLandmarkType.rightShoulder, PoseLandmarkType.rightElbow],
      [PoseLandmarkType.rightElbow, PoseLandmarkType.rightWrist],
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

    // ✅ Draw skeleton lines
    for (final pair in connections) {
      final a = lm[pair[0]];
      final b = lm[pair[1]];
      if (a == null || b == null) continue;
      canvas.drawLine(mapPoint(a.x, a.y), mapPoint(b.x, b.y), linePaint);
    }

    // ✅ Draw joints
    for (final l in lm.values) {
      canvas.drawCircle(mapPoint(l.x, l.y), 6, jointPaint);
    }

    // ✅ Draw elbow angle text
    final elbow = lm[PoseLandmarkType.rightElbow];
    if (elbowAngle != null && elbow != null) {
      final tp = TextPainter(
        text: TextSpan(
          text: '${elbowAngle!.toStringAsFixed(0)}°',
          style: const TextStyle(
            color: Colors.yellowAccent,
            fontSize: 14,
            fontWeight: FontWeight.bold,
            shadows: [Shadow(color: Colors.black, blurRadius: 4)],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, mapPoint(elbow.x, elbow.y) + const Offset(8, -20));
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BicepCurlPainter old) =>
      old.pose != pose ||
      old.elbowAngle != elbowAngle ||
      old.postureGood != postureGood;
}
