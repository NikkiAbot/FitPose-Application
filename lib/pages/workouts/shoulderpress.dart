import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import '../../../components/camera_widget.dart';

class ShoulderPressPage extends StatefulWidget {
  const ShoulderPressPage({super.key});

  @override
  State<ShoulderPressPage> createState() => _ShoulderPressPageState();
}

class _ShoulderPressPageState extends State<ShoulderPressPage> {
  final _showCamera = true;

  // Pose detector (same API as your BicepCurl page)
  late final PoseDetector _poseDetector = PoseDetector(
    options: PoseDetectorOptions(mode: PoseDetectionMode.stream),
  );

  bool _isProcessing = false;
  int _lastProcessMs = 0;

  Pose? _latestPose;
  int? _imageWidth;
  int? _imageHeight;

  // Metrics
  double? _leftElbow;
  double? _rightElbow;
  double? _avgElbow;
  double? _trunkAngle;
  String _feedback = 'Face the camera and stand tall';
  String _postureStatus = 'Tracking...';
  bool _postureGood = false;

  // FSM for reps
  int _reps = 0;
  String _state = 'waiting'; // waiting | lowered | raised
  bool _anomaly = false;

  static const double loweredThresh = 90; // down
  static const double raisedThresh = 160; // up
  static const double maxTorsoLeanDeg = 15; // posture tolerance
  static const double maxAsymmetryDeg = 12; // elbows diff

  // Use portrait 270 like your working BicepCurl page
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

  // === Camera frame handler (same throttle style as your curl page) ===
  void _onCameraImage(
    CameraImage image,
    int rotationDegrees,
    bool isFrontCamera,
  ) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_isProcessing || now - _lastProcessMs < 120) return;
    _isProcessing = true;
    _lastProcessMs = now;

    // Lock to portrait like BicepCurl
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
          format: InputImageFormat.nv21, // matches the NV21 byte layout above
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
      if (kDebugMode) print('[ShoulderPress] Exception: $e');
      _latestPose = null;
      _feedback = 'Error processing frame';
      _postureStatus = 'Tracking...';
      _postureGood = false;
    }
  }

  // Same converter you use in BicepCurl (YUV420 -> NV21)
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

  // Angle at the middle point b (a-b-c), using standard dot-product formula
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

  // Compute angles + rep logic similar to your Python FSM
  void _analyzePose(Pose pose) {
    final lm = pose.landmarks;

    final ls = lm[PoseLandmarkType.leftShoulder];
    final rs = lm[PoseLandmarkType.rightShoulder];
    final le = lm[PoseLandmarkType.leftElbow];
    final re = lm[PoseLandmarkType.rightElbow];
    final lw = lm[PoseLandmarkType.leftWrist];
    final rw = lm[PoseLandmarkType.rightWrist];
    final lh = lm[PoseLandmarkType.leftHip];
    final rh = lm[PoseLandmarkType.rightHip];

    if ([ls, rs, le, re, lw, rw, lh, rh].any((p) => p == null)) {
      _feedback = 'Move fully into view';
      _postureStatus = 'Tracking...';
      _postureGood = false;
      return;
    }

    // Elbow angles (both arms)
    _leftElbow = _angle(
      Offset(ls!.x, ls.y),
      Offset(le!.x, le.y),
      Offset(lw!.x, lw.y),
    );
    _rightElbow = _angle(
      Offset(rs!.x, rs.y),
      Offset(re!.x, re.y),
      Offset(rw!.x, rw.y),
    );
    _avgElbow = ((_leftElbow ?? 0) + (_rightElbow ?? 0)) / 2.0;

    // Trunk angle as lean (approx): angle between mid-hip -> mid-shoulder vector and vertical
    final midSh = Offset((ls.x + rs.x) / 2, (ls.y + rs.y) / 2);
    final midHp = Offset((lh!.x + rh!.x) / 2, (lh.y + rh.y) / 2);
    final torsoVec = midSh - midHp;
    _trunkAngle =
        (180 / math.pi) * math.atan2(torsoVec.dx.abs(), torsoVec.dy.abs());

    // Posture quality
    final elbowsDiff = ((_leftElbow ?? 0) - (_rightElbow ?? 0)).abs();
    final upright = _trunkAngle! < maxTorsoLeanDeg;
    final symmetric = elbowsDiff < maxAsymmetryDeg;
    _postureGood = upright && symmetric;
    _postureStatus =
        _postureGood
            ? 'Good Posture'
            : (!upright ? 'Don’t arch/lean' : 'Keep arms symmetric');

    // FSM transitions
    if (_state == 'waiting') {
      if (_avgElbow! < loweredThresh) {
        _state = 'lowered';
        _anomaly = false;
      }
    } else if (_state == 'lowered') {
      if (_avgElbow! > raisedThresh) {
        _state = 'raised';
        if (!_postureGood) _anomaly = true;
      }
    } else if (_state == 'raised') {
      if (_avgElbow! < loweredThresh) {
        if (!_anomaly && _postureGood) {
          _reps += 1;
          _feedback = 'Rep ✓';
        } else {
          _feedback = 'Fix form for clean rep';
        }
        _state = 'lowered';
        _anomaly = false;
      }
    }

    // Live feedback
    if (_state == 'lowered' && _avgElbow! < 70) {
      _feedback = _postureGood ? 'Drive up!' : _postureStatus;
    } else if (_state == 'raised' && _avgElbow! > 170) {
      _feedback = _postureGood ? 'Control the descent' : _postureStatus;
    } else {
      _feedback = _postureGood ? 'Keep going' : _postureStatus;
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
                Icon(Icons.fitness_center, color: Colors.purple, size: 26),
                SizedBox(width: 8),
                Text(
                  'Shoulder Press',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            content: const SingleChildScrollView(
              child: Text(
                '1) Stand tall, feet shoulder-width\n'
                '2) Palms forward at shoulder level\n'
                '3) Press straight overhead\n'
                '4) Keep core braced (no back arch)\n'
                '5) Lower to shoulder level each rep\n\n'
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
        title: const Text('Shoulder Press'),
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
                  // Non-mirrored camera (true image)
                  CameraWidget(
                    showCamera: _showCamera,
                    onImage: _onCameraImage,
                    // If you want to hard-lock rotation to 90:
                    // forcedRotationDegrees: 90,
                  ),

                  // Overlay painter (only if we have a pose + image size)
                  if (_latestPose != null &&
                      _imageWidth != null &&
                      _imageHeight != null)
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _ShoulderPressPainter(
                          pose: _latestPose!,
                          imageWidth: _imageWidth!,
                          imageHeight: _imageHeight!,
                          leftElbow: _leftElbow,
                          rightElbow: _rightElbow,
                          avgElbow: _avgElbow,
                          trunkAngle: _trunkAngle,
                          postureGood: _postureGood,
                          rotation: _rotation,
                          mirror: false, // non-mirrored preview → false
                        ),
                      ),
                    ),

                  // HUD
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
                            if (_avgElbow != null)
                              Text(
                                'Avg Elbow: ${_avgElbow!.toStringAsFixed(0)}°',
                              ),
                            if (_leftElbow != null && _rightElbow != null)
                              Text(
                                'L/R Elbow: ${_leftElbow!.toStringAsFixed(0)}° / ${_rightElbow!.toStringAsFixed(0)}°',
                              ),
                            if (_trunkAngle != null)
                              Text(
                                'Trunk: ${_trunkAngle!.toStringAsFixed(0)}°',
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

// === Painter to draw skeleton & angle labels ===
class _ShoulderPressPainter extends CustomPainter {
  final Pose pose;
  final int imageWidth;
  final int imageHeight;
  final double? leftElbow;
  final double? rightElbow;
  final double? avgElbow;
  final double? trunkAngle;
  final bool postureGood;
  final InputImageRotation rotation;
  final bool mirror;

  _ShoulderPressPainter({
    required this.pose,
    required this.imageWidth,
    required this.imageHeight,
    required this.leftElbow,
    required this.rightElbow,
    required this.avgElbow,
    required this.trunkAngle,
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

    final scaleX = size.width / effW;
    final scaleY = size.height / effH;

    Offset mapPoint(double x, double y) {
      final mappedX = size.width - (x * scaleX); // always flip X
      final mappedY = y * scaleY; // keep Y as-is (no flip)
      return Offset(mappedX, mappedY);
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

    // Lines
    for (final pair in connections) {
      final a = lm[pair[0]];
      final b = lm[pair[1]];
      if (a == null || b == null) continue;
      canvas.drawLine(mapPoint(a.x, a.y), mapPoint(b.x, b.y), linePaint);
    }

    // Joints
    for (final l in lm.values) {
      canvas.drawCircle(mapPoint(l.x, l.y), 6, jointPaint);
    }

    // Angle labels near elbows + avg near shoulders
    final le = lm[PoseLandmarkType.leftElbow];
    final re = lm[PoseLandmarkType.rightElbow];
    final ls = lm[PoseLandmarkType.leftShoulder];
    final rs = lm[PoseLandmarkType.rightShoulder];

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

    if (leftElbow != null && le != null) {
      drawLabel(
        '${leftElbow!.toStringAsFixed(0)}°',
        mapPoint(le.x, le.y) + const Offset(8, -20),
      );
    }
    if (rightElbow != null && re != null) {
      drawLabel(
        '${rightElbow!.toStringAsFixed(0)}°',
        mapPoint(re.x, re.y) + const Offset(8, -20),
      );
    }
    if (avgElbow != null && ls != null && rs != null) {
      final mid = Offset((ls.x + rs.x) / 2, (ls.y + rs.y) / 2);
      drawLabel(
        'AVG ${avgElbow!.toStringAsFixed(0)}°',
        mapPoint(mid.dx, mid.dy) + const Offset(8, -24),
      );
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ShoulderPressPainter old) =>
      old.pose != pose ||
      old.leftElbow != leftElbow ||
      old.rightElbow != rightElbow ||
      old.avgElbow != avgElbow ||
      old.postureGood != postureGood;
}
