import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:flutter/services.dart';
import 'package:onnxruntime/onnxruntime.dart';

import '../../components/camera_widget.dart';

class Squats extends StatefulWidget {
  const Squats({super.key});

  @override
  State<Squats> createState() => _SquatsState();
}

class _SquatsState extends State<Squats> {
  bool _showCamera = true;

  // Pose detector
  late final PoseDetector _poseDetector = PoseDetector(
    options: PoseDetectorOptions(mode: PoseDetectionMode.stream),
  );

<<<<<<< Updated upstream
  // Frame processing control
=======
  OrtSession? _onnxSession;

>>>>>>> Stashed changes
  bool _isProcessing = false;
  int _lastProcessMs = 0;

  // Raw pose
  Pose? _latestPose;

  // Image size (for scaling)
  int? _imageWidth;
  int? _imageHeight;

  // Metrics
  double? _kneeAngle;
  double? _torsoAngle;
  double? _depthPercent;
  String _feedback = 'Face camera at 45° and start';
  String _postureStatus = 'Tracking...';
  bool _postureGood = false;

  // Rep logic
  int _squatReps = 0;
  bool _inRep = false;
  bool _bottomReached = false;
  bool _repPostureGood = true;

  // Thresholds
<<<<<<< Updated upstream
  static const double standingAngleThreshold = 165;
  static const double bottomAngleThreshold =
      80; // was 100; require ≤80° at bottom
  static const double deepAngle =
      80; // was 95; align guidance with target depth
  static const double maxTorsoLeanDeg = 25;
  static const double maxHipLevelRatio = 0.05;
=======
  static const double downThresh = 90;
  static const double upThresh = 160;
  static const double maxTorsoLeanDeg = 20;
  static const double maxAsymmetryDeg = 15;
>>>>>>> Stashed changes

  // Rotation assumption
  InputImageRotation _rotation = InputImageRotation.rotation0deg;

  int _consecutiveFail = 0;

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

<<<<<<< Updated upstream
  // Camera image callback
=======
  Future<void> _loadOnnxModel() async {
    try {
      OrtEnv.instance.init();
      final bytes =
          (await rootBundle.load(
            'assets/models/your_model.onnx',
          )).buffer.asUint8List();
      final options = OrtSessionOptions();
      _onnxSession = OrtSession.fromBuffer(bytes, options);
    } catch (e) {
      if (kDebugMode) print('[ONNX] Failed to load model: $e');
    }
  }

>>>>>>> Stashed changes
  void _onCameraImage(
    CameraImage image,
    int rotationDegrees,
    bool isFrontCamera,
  ) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_isProcessing || now - _lastProcessMs < 120) return;
    _isProcessing = true;
    _lastProcessMs = now;

    _processPose(image).whenComplete(() {
      _isProcessing = false;
      if (mounted) setState(() {});
    });
  }

  Future<void> _processPose(CameraImage image) async {
    try {
      _imageWidth ??= image.width;
      _imageHeight ??= image.height;

      // Build NV21 buffer from 3-plane YUV420
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

      if (kDebugMode) {
        print(
          '[Pose] poses=${poses.length} rot=$_rotation fail=$_consecutiveFail nv21=${nv21.length}',
        );
      }

      if (poses.isEmpty) {
        _consecutiveFail++;
        if (_consecutiveFail == 8) {
          final next =
              _rotation == InputImageRotation.rotation0deg
                  ? InputImageRotation.rotation270deg
                  : (_rotation == InputImageRotation.rotation270deg
                      ? InputImageRotation.rotation90deg
                      : InputImageRotation.rotation0deg);
          if (kDebugMode) {
            print('[Pose] rotation fallback $_rotation -> $next');
          }
          _rotation = next;
          _consecutiveFail = 0;
        }

        // Clear state to avoid HUD/painter glitches and stuck rep state
        _latestPose = null;
        _kneeAngle = null;
        _torsoAngle = null;
        _depthPercent = null;
        _inRep = false;
        _bottomReached = false;
        _repPostureGood = true;

        _feedback = 'No pose detected';
        _postureStatus = 'Tracking...';
        _postureGood = false;
        return;
      }

      _consecutiveFail = 0;
      _latestPose = poses.first;

      // --- Run rule-based analysis ---
      _analyzePose(_latestPose!);

      // --- Run ONNX model ---
      await _analyzeWithOnnx(_latestPose!);
    } catch (e) {
      if (kDebugMode) {
        print('[Pose] Exception convert: $e');
      }
      _latestPose = null;
      _feedback = 'Conversion error';
      _postureStatus = 'Tracking...';
      _postureGood = false;
    }
  }

  // Convert 3-plane YUV420 (camera) -> NV21 byte array
  Uint8List _yuv420ToNv21(CameraImage image) {
    final int width = image.width;
    final int height = image.height;
    final int ySize = width * height;
    final int chromaWidth = width ~/ 2;
    final int chromaHeight = height ~/ 2;
    final int chromaSize = chromaWidth * chromaHeight;
    final out = Uint8List(ySize + 2 * chromaSize);

    final Plane yPlane = image.planes[0];
    final Plane uPlane = image.planes[1];
    final Plane vPlane = image.planes[2];

    int outIndex = 0;
    final int yRowStride = yPlane.bytesPerRow;
    final Uint8List yBytes = yPlane.bytes;
    for (int row = 0; row < height; row++) {
      final int start = row * yRowStride;
      out.setRange(outIndex, outIndex + width, yBytes, start);
      outIndex += width;
    }

    final int uRowStride = uPlane.bytesPerRow;
    final int vRowStride = vPlane.bytesPerRow;
    final int uPixelStride = uPlane.bytesPerPixel ?? 1;
    final int vPixelStride = vPlane.bytesPerPixel ?? 1;
    final Uint8List uBytes = uPlane.bytes;
    final Uint8List vBytes = vPlane.bytes;

    int chromaOut = ySize;

    for (int row = 0; row < chromaHeight; row++) {
      for (int col = 0; col < chromaWidth; col++) {
        final int uIndex = row * uRowStride + col * uPixelStride;
        final int vIndex = row * vRowStride + col * vPixelStride;
        out[chromaOut++] = vBytes[vIndex];
        out[chromaOut++] = uBytes[uIndex];
      }
    }
    return out;
  }

  double _angle(Offset a, Offset b, Offset c) {
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

    final hipL = lm[PoseLandmarkType.leftHip];
    final kneeL = lm[PoseLandmarkType.leftKnee];
    final ankleL = lm[PoseLandmarkType.leftAnkle];

    final hipR = lm[PoseLandmarkType.rightHip];
    final kneeR = lm[PoseLandmarkType.rightKnee];
    final ankleR = lm[PoseLandmarkType.rightAnkle];

    final shoulderL = lm[PoseLandmarkType.leftShoulder];
    final shoulderR = lm[PoseLandmarkType.rightShoulder];

    double? angleLeft;
    double? angleRight;

    if (hipL != null && kneeL != null && ankleL != null) {
      angleLeft = _angle(
        Offset(hipL.x, hipL.y),
        Offset(kneeL.x, kneeL.y),
        Offset(ankleL.x, ankleL.y),
      );
    }
    if (hipR != null && kneeR != null && ankleR != null) {
      angleRight = _angle(
        Offset(hipR.x, hipR.y),
        Offset(kneeR.x, kneeR.y),
        Offset(ankleR.x, ankleR.y),
      );
    }

    final kneeAngle =
        (angleLeft != null && angleRight != null)
            ? math.min(angleLeft, angleRight)
            : (angleLeft ?? angleRight);

    _kneeAngle = kneeAngle;

    if (kneeAngle == null ||
        hipL == null ||
        hipR == null ||
        shoulderL == null ||
        shoulderR == null) {
      _feedback = 'Move into view';
      _postureStatus = 'Tracking...';
      _postureGood = false;
      return;
    }

    // Hip level balance
    (hipL.y - hipR.y).abs();

    // Map camera coordinates to math coordinates (Y-up)
    Offset mapYUp(Offset p) => Offset(p.dx, _imageHeight! - p.dy);

    final midShoulder = Offset(
      (shoulderL.x + shoulderR.x) / 2,
      (shoulderL.y + shoulderR.y) / 2,
    );
    final midHip = Offset((hipL.x + hipR.x) / 2, (hipL.y + hipR.y) / 2);

<<<<<<< Updated upstream
    final shoulderFlipped = mapYUp(midShoulder);
    final hipFlipped = mapYUp(midHip);

    final torsoVec = shoulderFlipped - hipFlipped;

    if (torsoVec.distance > 0) {
      // vertical = straight up
      final vertical = const Offset(0, 1);

      final torsoNorm = torsoVec / torsoVec.distance;
      double dot = (torsoNorm.dx * vertical.dx + torsoNorm.dy * vertical.dy)
          .clamp(-1.0, 1.0);

      // Angle to vertical (upright ≈ 0°)
      final angleToVertical = math.acos(dot) * 180 / math.pi;

      // Display/logic as angle from horizontal, unsigned (upright ≈ 90°)
      _torsoAngle = (90 - angleToVertical).abs();

      // Posture check: allow up to maxTorsoLeanDeg from upright (90°)
      // e.g., with 25°, any torsoAngle >= 65° is considered good
      final torsoOk = _torsoAngle! >= (90 - maxTorsoLeanDeg);

      final hipDiff = (hipL.y - hipR.y).abs();
      final hipLevelOk =
          (_imageHeight != null && _imageHeight! > 0)
              ? hipDiff / _imageHeight! < maxHipLevelRatio
              : true;
      _postureGood = torsoOk && hipLevelOk;
      _postureStatus = _postureGood ? 'Correct Posture' : 'Incorrect Posture';
    } else {
      _torsoAngle = null; // no reliable torso, hide value
      _postureGood = false;
      _postureStatus = 'Tracking...';
=======
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
>>>>>>> Stashed changes
    }
  }

<<<<<<< Updated upstream
    // Depth percent (170 -> 90 mapped to 0..1)
    final clamped = (170 - kneeAngle).clamp(0, 80);
    _depthPercent = (clamped / 80).clamp(0, 1);

    // Rep state machine
    if (!_inRep && kneeAngle < standingAngleThreshold - 10) {
      _inRep = true;
      _bottomReached = false;
      _repPostureGood = _postureGood;
    }

    if (_inRep) {
      _repPostureGood &= _postureGood;

      if (!_bottomReached && kneeAngle <= bottomAngleThreshold) {
        _bottomReached = true;
      }

      if (_bottomReached && kneeAngle >= standingAngleThreshold) {
        if (_repPostureGood) {
          _squatReps += 1;
          _feedback = 'Good rep!';
        } else {
          _feedback = 'Posture off';
        }
        _inRep = false;
      } else {
        // Feedback guidance
        if (kneeAngle > 150) {
          _feedback = 'Start descent';
        } else if (kneeAngle > 130) {
          _feedback = 'Sit hips back';
        } else if (kneeAngle > 110) {
          _feedback = 'Go deeper';
        } else if (kneeAngle > deepAngle) {
          _feedback = 'Almost there';
        } else {
          _feedback = _postureGood ? 'Hold depth' : 'Adjust posture';
        }
      }
    } else {
      _feedback = 'Start descent';
=======
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
>>>>>>> Stashed changes
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
                  'Squats',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            content: const SingleChildScrollView(
              child: Text(
                '1. Stand feet shoulder-width apart\n'
                '2. Keep chest up, neutral spine\n'
                '3. Sit hips back and down\n'
                '4. Thighs parallel or slightly below\n'
                '5. Drive up through heels\n'
                '6. Knees track over toes\n\n'
                'Camera will guide depth & posture.',
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

  void _showInstructionsAgain() => _showInstructionsDialog();

  @override
  Widget build(BuildContext context) {
    final hudColor = _postureGood ? Colors.green : Colors.redAccent;
    return Scaffold(
<<<<<<< Updated upstream
      appBar:
          _showCamera
              ? AppBar(
                title: const Text('Squats'),
                backgroundColor: Colors.black.withValues(alpha: 0.7),
                foregroundColor: Colors.white,
                elevation: 0,
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => Navigator.pop(context),
                ),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.info_outline),
                    onPressed: _showInstructionsAgain,
                  ),
                  IconButton(
                    icon: const Icon(Icons.videocam_off),
                    onPressed: () => setState(() => _showCamera = false),
                  ),
                ],
              )
              : AppBar(
                title: const Text('Squats'),
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => Navigator.pop(context),
                ),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.videocam),
                    onPressed: () => setState(() => _showCamera = true),
                  ),
                ],
              ),
=======
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
>>>>>>> Stashed changes
      body:
          _showCamera
              ? Stack(
                children: [
                  CameraWidget(
                    showCamera: _showCamera,
                    onImage: _onCameraImage,
                    onToggleCamera:
                        () => setState(() => _showCamera = !_showCamera),
                  ),
                  if (_latestPose != null &&
                      _imageWidth != null &&
                      _imageHeight != null)
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _SquatPosePainter(
                          pose: _latestPose!,
                          imageWidth: _imageWidth!,
                          imageHeight: _imageHeight!,
                          kneeAngle: _kneeAngle,
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
                            Wrap(
                              spacing: 12,
                              runSpacing: 4,
                              children: [
                                Text(
                                  'Reps: $_squatReps',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                if (_kneeAngle != null)
                                  Text(
                                    'Knee: ${_kneeAngle!.toStringAsFixed(0)}°',
                                  ),
                                if (_torsoAngle != null)
                                  Text(
                                    'Torso: ${_torsoAngle!.toStringAsFixed(0)}°',
                                  ),
                                Text(
                                  _postureStatus,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: hudColor,
                                  ),
                                ),
                              ],
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
                  Positioned(
                    right: 12,
                    top: 100,
                    bottom: 100,
                    child:
                        _depthPercent == null
                            ? const SizedBox()
                            : CustomPaint(
                              size: const Size(24, double.infinity),
                              painter: _DepthBarPainter(_depthPercent!),
                            ),
                  ),
                ],
              )
              : _instructionsView(),
    );
  }

  Widget _instructionsView() {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Squats',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          const Text(
            'Instructions:',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          const Text(
            '1. Stand feet shoulder-width apart\n'
            '2. Keep chest up\n'
            '3. Sit hips back & down\n'
            '4. Thighs parallel or slightly below\n'
            '5. Drive up through heels\n'
            '6. Knees track over toes',
            style: TextStyle(fontSize: 18, height: 1.5),
          ),
          const SizedBox(height: 32),
          Center(
            child: ElevatedButton.icon(
              onPressed: () => setState(() => _showCamera = true),
              icon: const Icon(Icons.videocam),
              label: const Text('Start Camera'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
                textStyle: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Painter for skeleton + angles
class _SquatPosePainter extends CustomPainter {
  final bool mirror;
  final Pose pose;
  final int imageWidth;
  final int imageHeight;
  final double? kneeAngle;
  final double? torsoAngle;
  final bool postureGood;
  final InputImageRotation rotation;

  _SquatPosePainter({
    required this.mirror,
    required this.pose,
    required this.imageWidth,
    required this.imageHeight,
    required this.kneeAngle,
    required this.torsoAngle,
    required this.postureGood,
    required this.rotation,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();

    final rotated =
        rotation == InputImageRotation.rotation90deg ||
        rotation == InputImageRotation.rotation270deg;
    final effW = rotated ? imageHeight : imageWidth;
    final effH = rotated ? imageWidth : imageHeight;

    final canvasPortrait = size.height > size.width;
    final sourceLandscape = effW > effH;
    bool rotatedCanvas = false;
    if (canvasPortrait && sourceLandscape) {
      canvas.translate(0, size.height);
      canvas.rotate(-math.pi / 2);
      rotatedCanvas = true;
    }

    final double targetW = rotatedCanvas ? size.height : size.width;
    final double targetH = rotatedCanvas ? size.width : size.height;
    final scaleX = targetW / effW;
    final scaleY = targetH / effH;

    final lm = pose.landmarks;

    Offset mapPoint(double x, double y) {
      // Flip Y if needed
      final flippedY = targetH - (y * scaleY); // y axis is reversed
      return Offset(x * scaleX, flippedY);
    }

    final connections = <List<PoseLandmarkType>>[
      [PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder],
      [PoseLandmarkType.leftHip, PoseLandmarkType.rightHip],
      [PoseLandmarkType.leftShoulder, PoseLandmarkType.leftElbow],
      [PoseLandmarkType.leftElbow, PoseLandmarkType.leftWrist],
      [PoseLandmarkType.rightShoulder, PoseLandmarkType.rightElbow],
      [PoseLandmarkType.rightElbow, PoseLandmarkType.rightWrist],
      [PoseLandmarkType.leftShoulder, PoseLandmarkType.leftHip],
      [PoseLandmarkType.rightShoulder, PoseLandmarkType.rightHip],
      [PoseLandmarkType.leftHip, PoseLandmarkType.leftKnee],
      [PoseLandmarkType.leftKnee, PoseLandmarkType.leftAnkle],
      [PoseLandmarkType.rightHip, PoseLandmarkType.rightKnee],
      [PoseLandmarkType.rightKnee, PoseLandmarkType.rightAnkle],
    ];

    final linePaint =
        Paint()
          ..color = Colors.white70
          ..strokeWidth = 2;
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

<<<<<<< Updated upstream
    void drawLabel(String text, PoseLandmark? landmark, Color color) {
      if (landmark == null) return;
      final p = mapPoint(landmark.x, landmark.y);
=======
    void drawLabel(String text, Offset where) {
>>>>>>> Stashed changes
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            color: color,
            fontSize: 14,
            fontWeight: FontWeight.bold,
            shadows: const [Shadow(color: Colors.black87, blurRadius: 4)],
          ),
        ),
        maxLines: 1,
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, p + const Offset(8, -20));
    }

<<<<<<< Updated upstream
    final knee =
        lm[PoseLandmarkType.leftKnee] ?? lm[PoseLandmarkType.rightKnee];
    if (kneeAngle != null) {
      drawLabel('${kneeAngle!.toStringAsFixed(0)}°', knee, Colors.yellowAccent);
    }

    final shoulderL = lm[PoseLandmarkType.leftShoulder];
    final shoulderR = lm[PoseLandmarkType.rightShoulder];
    if (torsoAngle != null && shoulderL != null && shoulderR != null) {
      final midX = (shoulderL.x + shoulderR.x) / 2;
      final midY = (shoulderL.y + shoulderR.y) / 2;
      final dummy = PoseLandmark(
        type: PoseLandmarkType.leftShoulder,
        x: midX,
        y: midY,
        z: 0,
        likelihood: 1,
      );
=======
    final lk = lm[PoseLandmarkType.leftKnee];
    final rk = lm[PoseLandmarkType.rightKnee];
    final lh = lm[PoseLandmarkType.leftHip];
    final rh = lm[PoseLandmarkType.rightHip];

    if (leftKnee != null && lk != null) {
>>>>>>> Stashed changes
      drawLabel(
        '${torsoAngle!.toStringAsFixed(0)}° torso',
        dummy,
        Colors.cyanAccent,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SquatPosePainter old) =>
      old.pose != pose ||
      old.kneeAngle != kneeAngle ||
      old.torsoAngle != torsoAngle ||
      old.postureGood != postureGood ||
      old.imageWidth != imageWidth ||
      old.imageHeight != imageHeight ||
      old.rotation != rotation;
}

// Depth bar painter remains unchanged...
class _DepthBarPainter extends CustomPainter {
  final double depth;
  _DepthBarPainter(this.depth);

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()..color = Colors.white24;
    final fg =
        Paint()
          ..shader = const LinearGradient(
            colors: [Colors.indigo, Colors.greenAccent],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      const Radius.circular(8),
    );
    canvas.drawRRect(rect, bg);

    final h = size.height * depth;
    final fill = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, size.height - h, size.width, h),
      const Radius.circular(8),
    );
    canvas.drawRRect(fill, fg);
  }

  @override
  bool shouldRepaint(covariant _DepthBarPainter old) => old.depth != depth;
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
