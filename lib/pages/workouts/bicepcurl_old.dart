import 'dart:math' as math;
import 'dart:collection'; // For Queue
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import '../../components/camera_widget.dart';
import '../../models/bicepcurl_feature_extract.dart';
import '../../models/bicep_knn_classifier.dart';

class BicepCurl extends StatefulWidget {
  const BicepCurl({super.key});

  @override
  State<BicepCurl> createState() => _BicepCurlState();
}

class _BicepCurlState extends State<BicepCurl> {
  final _showCamera = true;
  late final PoseDetector _poseDetector = PoseDetector(
    options: PoseDetectorOptions(
      mode: PoseDetectionMode.stream,
      model: PoseDetectionModel.accurate,
    ),
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

  // ═══════════════════════════════════════════════════════════════
  // ML CLASSIFIER
  // ═══════════════════════════════════════════════════════════════
  final BicepKNNClassifier _classifier = BicepKNNClassifier();
  bool _classifierReady = false;
  String _mlLabel = 'neutral';
  double _mlConfidence = 0.0;

  // ═══════════════════════════════════════════════════════════════
  // SMOOTHING BUFFERS (W=5 frames, matching Python)
  // ═══════════════════════════════════════════════════════════════
  static const int bufferSize = 5;
  final Queue<double> _dxBuffer = Queue();
  final Queue<double> _inclBuffer = Queue();
  final Queue<double> _angBuffer = Queue();
  final Queue<double> _velBuffer = Queue();
  final Queue<double> _whBuffer = Queue();
  final Queue<double> _mcBuffer = Queue();
  final Queue<double> _romBuffer = Queue();

  // For velocity calculation
  double? _previousAngle;
  double _previousTime = 0.0;

  // ═══════════════════════════════════════════════════════════════
  // THRESHOLDS (exactly matching Python)
  // ═══════════════════════════════════════════════════════════════
  static const double swingThreshold = 0.06;    // SWING_TH
  static const double leanThreshold = -165.0;   // LEAN_TH
  static const double downThreshold = 75.0;     // DOWN_TH
  static const double upThreshold = 149.0;      // UP_TH

  InputImageRotation _rotation = InputImageRotation.rotation270deg;

  // ═══════════════════════════════════════════════════════════════
  // FSM STATE TRACKING (matching Python exactly)
  // ═══════════════════════════════════════════════════════════════
  String _fsmState = 'extended'; // 'extended' or 'flexed'
  bool _cycleOk = false;
  String _instruction = 'neutral';

  @override
  void initState() {
    super.initState();
    _initializeClassifier();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _showInstructionsDialog(),
    );
  }

  Future<void> _initializeClassifier() async {
    await _classifier.initialize();
    if (mounted) {
      setState(() {
        _classifierReady = _classifier.isReady;
      });
    }
    if (kDebugMode) {
      print('[Bicep] Classifier ready: $_classifierReady');
    }
  }

  @override
  void dispose() {
    _poseDetector.close();
    _classifier.dispose();
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
      if (kDebugMode) print('[Bicep] Error processing pose: $e');
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

  void _analyzePose(Pose pose) {
    final lm = pose.landmarks;
    final shoulderR = lm[PoseLandmarkType.rightShoulder];
    final elbowR = lm[PoseLandmarkType.rightElbow];
    final wristR = lm[PoseLandmarkType.rightWrist];
    final hipR = lm[PoseLandmarkType.rightHip];

    if (shoulderR == null || elbowR == null || wristR == null || hipR == null) {
      _feedback = 'Move into view';
      _postureStatus = 'Tracking...';
      _postureGood = false;
      _instruction = 'neutral';
      return;
    }

    // ═══════════════════════════════════════════════════════════════
    // FEATURE EXTRACTION (matching Python's raw features)
    // ═══════════════════════════════════════════════════════════════
    
    final currentTime = DateTime.now().millisecondsSinceEpoch / 1000.0;
    
    final features = BicepCurlFeatureExtractor.extractFeatures(
      lm,
      _previousAngle ?? 0.0,
      _previousTime,
      currentTime,
    );

    // Update for next frame
    _previousAngle = features[0]; // elbow angle
    _previousTime = currentTime;

    // ═══════════════════════════════════════════════════════════════
    // SMOOTHING: Add to buffers (matching Python's deque behavior)
    // ═══════════════════════════════════════════════════════════════
    
    _addToBuffer(_angBuffer, features[0]);   // ang
    _addToBuffer(_dxBuffer, features[1]);    // dx
    _addToBuffer(_inclBuffer, features[2]);  // incl
    _addToBuffer(_velBuffer, features[3]);   // vel
    _addToBuffer(_whBuffer, features[4]);    // wh

    // Calculate MC and ROM from angle buffer (matching Python logic)
    if (_angBuffer.length >= 2) {
      final angleList = _angBuffer.toList();
      final angleStd = _calculateStd(angleList);
      final angleRange = _calculateRange(angleList);
      final mc = 1.0 - (angleStd / (angleRange + 1e-6));
      _addToBuffer(_mcBuffer, mc);
      _addToBuffer(_romBuffer, angleRange);
    }

    // ═══════════════════════════════════════════════════════════════
    // SMOOTHED SIGNALS (matching Python's np.mean(bufs[k]))
    // ═══════════════════════════════════════════════════════════════
    
    final angSmooth = _getBufferMean(_angBuffer);
    final dxSmooth = _getBufferMean(_dxBuffer);
    final inclSmooth = _getBufferMean(_inclBuffer);
    final velSmooth = _getBufferMean(_velBuffer);
    final whSmooth = _getBufferMean(_whBuffer);
    final mcSmooth = _getBufferMean(_mcBuffer);
    final romSmooth = _getBufferMean(_romBuffer);

    // Update display values
    _elbowAngle = angSmooth;
    _torsoAngle = inclSmooth;

    if (kDebugMode) {
      print('[DEBUG] incl_s=${inclSmooth.toStringAsFixed(1)}°, '
            'dx_s=${dxSmooth.toStringAsFixed(3)}, '
            'ang_s=${angSmooth.toStringAsFixed(1)}°');
    }

    // ═══════════════════════════════════════════════════════════════
    // INSTRUCTION FEEDBACK (matching Python step 5)
    // ═══════════════════════════════════════════════════════════════
    
    if (angSmooth > upThreshold) {
      _instruction = 'Raise weight fully';
    } else if (angSmooth < downThreshold) {
      _instruction = 'Lower weight fully';
    } else {
      _instruction = 'neutral';
    }

    // ═══════════════════════════════════════════════════════════════
    // FORM CLASSIFICATION (matching Python steps 6-7)
    // Priority: Threshold shortcuts → ML fallback
    // ═══════════════════════════════════════════════════════════════
    
    String formLabel = 'neutral';
    
    // Step 6: Threshold shortcuts (highest priority)
    if (dxSmooth > swingThreshold) {
      formLabel = 'swing';
      _postureGood = false;
      _postureStatus = 'Stop swinging!';
    } else if (inclSmooth < leanThreshold) {
      formLabel = 'lean';
      _postureGood = false;
      _postureStatus = 'Don\'t lean forward!';
    } else {
      // Step 7: ML fallback
      if (_classifierReady && _mcBuffer.length >= bufferSize) {
        final smoothedFeatures = [
          angSmooth,
          dxSmooth,
          inclSmooth,
          velSmooth,
          whSmooth,
          mcSmooth,
          romSmooth,
        ];

        final prediction = _classifier.predict(smoothedFeatures);
        _mlLabel = prediction['label'];
        _mlConfidence = prediction['confidence'];

        formLabel = _mlLabel;

        if (kDebugMode) {
          print('[ML] $_mlLabel @ ${(_mlConfidence * 100).toStringAsFixed(1)}%');
        }

        // Update posture status based on ML prediction
        if (_mlLabel == 'good') {
          _postureGood = true;
          _postureStatus = 'Good Form ✓';
        } else if (_mlLabel == 'half_rep') {
          _postureGood = false;
          _postureStatus = 'Complete full range!';
        } else if (_mlLabel == 'swing') {
          _postureGood = false;
          _postureStatus = 'Stop swinging!';
        } else if (_mlLabel == 'lean') {
          _postureGood = false;
          _postureStatus = 'Don\'t lean!';
        } else {
          _postureGood = false;
          _postureStatus = 'Maintain form';
        }
      } else {
        // Classifier not ready yet
        formLabel = 'neutral';
        _postureGood = true;
        _postureStatus = 'Tracking...';
      }
    }

    // ═══════════════════════════════════════════════════════════════
    // FSM & REP COUNTING (matching Python step 8 exactly)
    // ═══════════════════════════════════════════════════════════════
    
    // State transition: extended → flexed (lowering)
    if (_fsmState == 'extended' && angSmooth < downThreshold) {
      _cycleOk = true;
      _fsmState = 'flexed';
      if (kDebugMode) print('[FSM] extended → flexed');
    } 
    // State: flexed (during curl)
    else if (_fsmState == 'flexed') {
      // Track form during flexed phase
      // If bad form detected at any point, invalidate cycle
      if (inclSmooth < leanThreshold || 
          dxSmooth > swingThreshold || 
          formLabel != 'good') {
        _cycleOk = false;
      }
      
      // State transition: flexed → extended (raising)
      if (angSmooth > upThreshold) {
        if (_cycleOk) {
          _curlReps += 1;
          _feedback = 'Nice curl! ✓';
          if (kDebugMode) print('[FSM] ✅ Rep counted! Total: $_curlReps');
        } else {
          _feedback = 'Form issue - not counted';
          if (kDebugMode) print('[FSM] ❌ Rep NOT counted (bad form)');
        }
        _fsmState = 'extended';
        _cycleOk = false;
        if (kDebugMode) print('[FSM] flexed → extended');
      } else {
        // Progressive feedback during curl
        if (angSmooth > 100) {
          _feedback = 'Keep curling';
        } else if (angSmooth > 60) {
          _feedback = 'Almost there!';
        } else {
          _feedback = _postureGood ? 'Hold contraction' : 'Fix form!';
        }
      }
    }
    // State: extended (starting position)
    else if (_fsmState == 'extended') {
      if (angSmooth > upThreshold - 10) {
        _feedback = 'Start curling';
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // HELPER METHODS FOR SMOOTHING
  // ═══════════════════════════════════════════════════════════════
  
  void _addToBuffer(Queue<double> buffer, double value) {
    buffer.add(value);
    if (buffer.length > bufferSize) {
      buffer.removeFirst();
    }
  }

  double _getBufferMean(Queue<double> buffer) {
    if (buffer.isEmpty) return 0.0;
    return buffer.reduce((a, b) => a + b) / buffer.length;
  }

  double _calculateStd(List<double> values) {
    if (values.length < 2) return 0.0;
    final mean = values.reduce((a, b) => a + b) / values.length;
    final variance = values
        .map((v) => (v - mean) * (v - mean))
        .reduce((a, b) => a + b) / values.length;
    return math.sqrt(variance);
  }

  double _calculateRange(List<double> values) {
    if (values.isEmpty) return 0.0;
    final min = values.reduce(math.min);
    final max = values.reduce(math.max);
    return max - min;
  }

  // ═══════════════════════════════════════════════════════════════
  // UI BUILD METHOD
  // ═══════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final hudColor = _postureGood ? Colors.greenAccent : Colors.orangeAccent;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bicep Curl'),
        backgroundColor: Colors.black.withOpacity(0.7),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: _showInstructionsDialog,
          ),
        ],
      ),
      body: _showCamera
          ? Stack(
              children: [
                // Camera feed
                CameraWidget(
                  showCamera: _showCamera,
                  onImage: _onCameraImage,
                ),

                // Pose skeleton overlay
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

                // HUD overlay (matching Python's status box)
                Positioned(
                  top: 16,
                  left: 16,
                  right: 16,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF57510).withOpacity(0.9), // (245, 117, 16)
                      border: Border.all(color: hudColor, width: 2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: DefaultTextStyle(
                      style: const TextStyle(color: Colors.black, fontSize: 13),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          // FORM column
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'FORM',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                              ),
                              Text(
                                _mlLabel,
                                style: TextStyle(
                                  color: _mlLabel == 'good' 
                                      ? Colors.green 
                                      : Colors.red,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),

                          // STATUS column
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'STATUS',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                              ),
                              Text(
                                _fsmState,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),

                          // REPS column
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'REPS',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                              ),
                              Text(
                                '$_curlReps',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),

                          // INSTRUCTION column
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text(
                                  'INSTRUCTION',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                  ),
                                ),
                                Text(
                                  _instruction,
                                  style: const TextStyle(
                                    color: Colors.yellow,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Additional info (bottom)
                Positioned(
                  bottom: 16,
                  left: 16,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: DefaultTextStyle(
                      style: const TextStyle(color: Colors.white, fontSize: 11),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_elbowAngle != null)
                            Text('Elbow: ${_elbowAngle!.toStringAsFixed(0)}°'),
                          if (_torsoAngle != null)
                            Text('Torso: ${_torsoAngle!.toStringAsFixed(0)}°'),
                          if (_classifierReady)
                            Text(
                              'ML: ${(_mlConfidence * 100).toStringAsFixed(0)}%',
                              style: const TextStyle(fontSize: 10),
                            ),
                          Text(
                            _feedback,
                            style: TextStyle(
                              color: hudColor,
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

  // ═══════════════════════════════════════════════════════════════
  // INSTRUCTIONS DIALOG
  // ═══════════════════════════════════════════════════════════════

  void _showInstructionsDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
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
            '1. Stand straight with arms extended\n'
            '2. Keep elbows close to torso (don\'t swing)\n'
            '3. Don\'t lean forward or backward\n'
            '4. Curl forearm up fully\n'
            '5. Lower down completely\n\n'
            'Only clean reps with good form will count!\n\n'
            'States:\n'
            '• Extended: Arms down (starting position)\n'
            '• Flexed: Arms curled up\n\n'
            'Rep counts when transitioning from flexed → extended with good form.',
            style: TextStyle(fontSize: 13, height: 1.5),
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
}

// ═══════════════════════════════════════════════════════════════
// CUSTOM PAINTER FOR SKELETON OVERLAY
// ═══════════════════════════════════════════════════════════════

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

    final rotated = rotation == InputImageRotation.rotation90deg ||
        rotation == InputImageRotation.rotation270deg;
    final effW = rotated ? imageHeight : imageWidth;
    final effH = rotated ? imageWidth : imageHeight;

    final scaleX = size.width / effW;
    final scaleY = size.height / effH;

    Offset mapPoint(double x, double y) {
      final newX = mirror ? size.width - (x * scaleX) : x * scaleX;
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

    final linePaint = Paint()
      ..color = postureGood ? Colors.greenAccent : Colors.orangeAccent
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final jointPaint = Paint()
      ..color = postureGood ? Colors.green : Colors.orange
      ..style = PaintingStyle.fill;

    // Draw skeleton lines
    for (final pair in connections) {
      final a = lm[pair[0]];
      final b = lm[pair[1]];
      if (a == null || b == null) continue;
      canvas.drawLine(mapPoint(a.x, a.y), mapPoint(b.x, b.y), linePaint);
    }

    // Draw joints
    for (final l in lm.values) {
      canvas.drawCircle(mapPoint(l.x, l.y), 6, jointPaint);
    }

    // Draw elbow angle label
    final elbow = lm[PoseLandmarkType.rightElbow];
    if (elbowAngle != null && elbow != null) {
      final tp = TextPainter(
        text: TextSpan(
          text: '${elbowAngle!.toStringAsFixed(0)}°',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.bold,
            backgroundColor: Colors.black54,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, mapPoint(elbow.x, elbow.y) + const Offset(10, -15));
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BicepCurlPainter old) =>
      old.pose != pose ||
      old.elbowAngle != elbowAngle ||
      old.postureGood != postureGood;
}