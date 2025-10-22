import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import '../../components/camera_widget.dart';
import '../../models/lunges_feature_extract.dart';
import '../../models/lunges_stage_classifier.dart';
import '../../models/lunges_error_classifier.dart';

class Lunges extends StatefulWidget {
  const Lunges({super.key});

  @override
  State<Lunges> createState() => _LungesState();
}

class _LungesState extends State<Lunges> {
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

  // ═══════════════════════════════════════════════════════════════
  // CLASSIFIERS
  // ═══════════════════════════════════════════════════════════════
  final LungesStageClassifier _stageClassifier = LungesStageClassifier();
  final LungesErrorClassifier _errorClassifier = LungesErrorClassifier();
  bool _classifiersReady = false;

  // ═══════════════════════════════════════════════════════════════
  // STATE TRACKING (matching Python logic)
  // ═══════════════════════════════════════════════════════════════
  String _currentStage = ''; // 'init', 'mid', 'down'
  int _counter = 0;

  // Thresholds (matching Python)
  static const double predictionProbabilityThreshold = 0.8;
  static const List<double> angleThresholds = [60.0, 135.0];

  // Knee angle analysis results
  Map<String, dynamic>? _kneeAnalysis;
  
  // Error detection
  String? _errorClass;
  double? _errorProbability;

  // Stage prediction
  String? _stagePredictedClass;
  double? _stageProbability;

  InputImageRotation _rotation = InputImageRotation.rotation270deg;

  @override
  void initState() {
    super.initState();
    _initializeClassifiers();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _showInstructionsDialog(),
    );
  }

  Future<void> _initializeClassifiers() async {
    await Future.wait([
      _stageClassifier.initialize(),
      _errorClassifier.initialize(),
    ]);
    if (mounted) {
      setState(() {
        _classifiersReady = _stageClassifier.isReady && _errorClassifier.isReady;
      });
    }
    if (kDebugMode) {
      print('[Lunges] Classifiers ready: $_classifiersReady');
    }
  }

  @override
  void dispose() {
    _poseDetector.close();
    _stageClassifier.dispose();
    _errorClassifier.dispose();
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
        return;
      }

      _latestPose = poses.first;
      _analyzePose(_latestPose!);
    } catch (e) {
      if (kDebugMode) print('[Lunges] Error processing pose: $e');
      _latestPose = null;
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

    if (!_classifiersReady) {
      return;
    }

    try {
      // ═══════════════════════════════════════════════════════════════
      // 1) EXTRACT KEYPOINTS (52 features)
      // ═══════════════════════════════════════════════════════════════
      final features = LungesFeatureExtractor.extractImportantKeypoints(lm);

      // ═══════════════════════════════════════════════════════════════
      // 2) STAGE PREDICTION (I/M/D)
      // ═══════════════════════════════════════════════════════════════
      final stageResult = _stageClassifier.predict(features);
      _stagePredictedClass = stageResult['class'];
      _stageProbability = stageResult['probability'];

      // Update current stage based on prediction (matching Python logic)
      if (_stagePredictedClass == 'I' && _stageProbability! >= predictionProbabilityThreshold) {
        _currentStage = 'init';
      } else if (_stagePredictedClass == 'M' && _stageProbability! >= predictionProbabilityThreshold) {
        _currentStage = 'mid';
      } else if (_stagePredictedClass == 'D' && _stageProbability! >= predictionProbabilityThreshold) {
        // Count rep when transitioning from mid/init to down
        if (_currentStage == 'mid' || _currentStage == 'init') {
          _counter += 1;
        }
        _currentStage = 'down';
      }

      // ═══════════════════════════════════════════════════════════════
      // 3) KNEE ANGLE ANALYSIS
      // ═══════════════════════════════════════════════════════════════
      _kneeAnalysis = LungesFeatureExtractor.analyzeKneeAngle(
        lm,
        _currentStage,
        angleThresholds,
      );

      // ═══════════════════════════════════════════════════════════════
      // 4) ERROR DETECTION (Knee-Over-Toe) - Only in "down" stage
      // ═══════════════════════════════════════════════════════════════
      if (_currentStage == 'down') {
        final errorResult = _errorClassifier.predict(features);
        _errorClass = errorResult['class'];
        _errorProbability = errorResult['probability'];
      } else {
        _errorClass = null;
        _errorProbability = null;
      }

      if (kDebugMode) {
        print('[Lunges] Stage: $_currentStage ($_stagePredictedClass @ ${(_stageProbability! * 100).toStringAsFixed(0)}%) | '
              'Counter: $_counter | '
              'Error: $_errorClass @ ${_errorProbability != null ? (_errorProbability! * 100).toStringAsFixed(0) : "N/A"}%');
      }

    } catch (e) {
      if (kDebugMode) print('[Lunges] Analysis error: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // UI BUILD METHOD
  // ═══════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lunges'),
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
                      painter: _LungesPainter(
                        pose: _latestPose!,
                        imageWidth: _imageWidth!,
                        imageHeight: _imageHeight!,
                        kneeAnalysis: _kneeAnalysis,
                        currentStage: _currentStage,
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
                      border: Border.all(color: Colors.white70, width: 2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: DefaultTextStyle(
                      style: const TextStyle(color: Colors.black, fontSize: 13),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          // STAGE column
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'STAGE',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                              ),
                              Text(
                                _stageProbability != null 
                                    ? _stageProbability!.toStringAsFixed(2)
                                    : '0.00',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                ),
                              ),
                              Text(
                                _currentStage.isNotEmpty ? _currentStage : 'init',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),

                          // COUNTER column
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'COUNTER',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                              ),
                              Text(
                                '$_counter',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),

                          // K_O_T (Knee-Over-Toe) column
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'K_O_T',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                              ),
                              Text(
                                _errorProbability != null 
                                    ? _errorProbability!.toStringAsFixed(2)
                                    : '--',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                ),
                              ),
                              Text(
                                _errorClass ?? '--',
                                style: TextStyle(
                                  color: _errorClass == 'K' ? Colors.red : Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Knee angle info (bottom left)
                if (_kneeAnalysis != null)
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
                            Text(
                              'R Knee: ${(_kneeAnalysis!['right']['angle'] as double).toStringAsFixed(0)}°',
                              style: TextStyle(
                                color: _kneeAnalysis!['right']['error'] ? Colors.red : Colors.white,
                              ),
                            ),
                            Text(
                              'L Knee: ${(_kneeAnalysis!['left']['angle'] as double).toStringAsFixed(0)}°',
                              style: TextStyle(
                                color: _kneeAnalysis!['left']['error'] ? Colors.red : Colors.white,
                              ),
                            ),
                            if (_kneeAnalysis!['error'] as bool)
                              const Text(
                                'Check knee angles!',
                                style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
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
            Icon(Icons.fitness_center, color: Colors.orange, size: 26),
            SizedBox(width: 8),
            Text(
              'Lunges Exercise',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: const SingleChildScrollView(
          child: Text(
            '1. Stand upright with feet hip-width apart\n'
            '2. Step forward with one leg, lowering your hips\n'
            '3. Bend both knees to 90-degree angles\n'
            '4. Keep front knee over ankle, not past toes\n'
            '5. Push back to starting position and repeat\n'
            '6. Alternate legs or complete set on one side\n\n'
            'The app will:\n'
            '• Detect your stage (init/mid/down)\n'
            '• Count reps automatically\n'
            '• Check knee angles (60-135°)\n'
            '• Detect knee-over-toe errors',
            style: TextStyle(fontSize: 13, height: 1.5),
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
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

class _LungesPainter extends CustomPainter {
  final Pose pose;
  final int imageWidth;
  final int imageHeight;
  final Map<String, dynamic>? kneeAnalysis;
  final String currentStage;
  final InputImageRotation rotation;
  final bool mirror;

  _LungesPainter({
    required this.pose,
    required this.imageWidth,
    required this.imageHeight,
    required this.kneeAnalysis,
    required this.currentStage,
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

    // Draw pose connections
    final connections = [
      [PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder],
      [PoseLandmarkType.leftHip, PoseLandmarkType.rightHip],
      [PoseLandmarkType.leftShoulder, PoseLandmarkType.leftHip],
      [PoseLandmarkType.rightShoulder, PoseLandmarkType.rightHip],
      [PoseLandmarkType.leftHip, PoseLandmarkType.leftKnee],
      [PoseLandmarkType.leftKnee, PoseLandmarkType.leftAnkle],
      [PoseLandmarkType.rightHip, PoseLandmarkType.rightKnee],
      [PoseLandmarkType.rightKnee, PoseLandmarkType.rightAnkle],
    ];

    final linePaint = Paint()
      ..color = Colors.greenAccent
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final jointPaint = Paint()
      ..color = Colors.green
      ..style = PaintingStyle.fill;

    // Draw skeleton
    for (final pair in connections) {
      final a = lm[pair[0]];
      final b = lm[pair[1]];
      if (a == null || b == null) continue;
      canvas.drawLine(mapPoint(a.x, a.y), mapPoint(b.x, b.y), linePaint);
    }

    for (final l in lm.values) {
      canvas.drawCircle(mapPoint(l.x, l.y), 6, jointPaint);
    }

    // Draw knee angles
    if (kneeAnalysis != null) {
      final rightKnee = lm[PoseLandmarkType.rightKnee];
      final leftKnee = lm[PoseLandmarkType.leftKnee];

      if (rightKnee != null) {
        final rightAngle = kneeAnalysis!['right']['angle'] as double;
        final rightError = kneeAnalysis!['right']['error'] as bool;
        
        final tp = TextPainter(
          text: TextSpan(
            text: '${rightAngle.toStringAsFixed(0)}°',
            style: TextStyle(
              color: rightError ? Colors.red : Colors.white,
              fontSize: currentStage == 'down' && rightError ? 16 : 14,
              fontWeight: rightError ? FontWeight.bold : FontWeight.normal,
              backgroundColor: Colors.black54,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, mapPoint(rightKnee.x, rightKnee.y) + const Offset(10, -15));
      }

      if (leftKnee != null) {
        final leftAngle = kneeAnalysis!['left']['angle'] as double;
        final leftError = kneeAnalysis!['left']['error'] as bool;
        
        final tp = TextPainter(
          text: TextSpan(
            text: '${leftAngle.toStringAsFixed(0)}°',
            style: TextStyle(
              color: leftError ? Colors.red : Colors.white,
              fontSize: currentStage == 'down' && leftError ? 16 : 14,
              fontWeight: leftError ? FontWeight.bold : FontWeight.normal,
              backgroundColor: Colors.black54,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, mapPoint(leftKnee.x, leftKnee.y) + const Offset(10, -15));
      }
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _LungesPainter old) =>
      old.pose != pose ||
      old.kneeAnalysis != kneeAnalysis ||
      old.currentStage != currentStage;
}