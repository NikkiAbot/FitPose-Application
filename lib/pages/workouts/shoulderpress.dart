import 'dart:math' as math;
import 'package:fitpose/models/shoulderpress_feature_extract.dart';
import 'package:fitpose/models/shoulder_press_classifier.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import '../../../components/camera_widget.dart';

class ShoulderPress extends StatefulWidget {
  const ShoulderPress({super.key});

  @override
  State<ShoulderPress> createState() => _ShoulderPressState();
}

class _ShoulderPressState extends State<ShoulderPress> {
  final _showCamera = true;

  // Pose detector
  late final PoseDetector _poseDetector = PoseDetector(
    options: PoseDetectorOptions(
      mode: PoseDetectionMode.stream, // Keep stream for real-time
      model: PoseDetectionModel.accurate,
    ),
  );

  // ML Classifier
  final ShoulderPressClassifier _classifier = ShoulderPressClassifier();
  bool _classifierReady = false;

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

  // ML Model predictions
  String _mlLabel = 'Initializing...';
  double _mlConfidence = 0.0;
  bool _mlGoodForm = false;

  // FSM for reps
  int _reps = 0;
  String _state = 'waiting'; // waiting | lowered | raised
  bool _anomaly = false;

  // Rule-based elbows flaring detection
  double? _leftElbowFlare;
  double? _rightElbowFlare;
  bool _elbowsFlaringDetected = false;
  String _flaringDetails = '';

  static const double loweredThresh = 90; // down
  static const double raisedThresh = 100; // up
  static const double minTorsoAngleDeg = 88; // ADDED: Below this = arching back
  static const double maxTorsoAngleDeg = 100; // Above this = leaning forward
  static const double maxAsymmetryDeg =
      25; // elbows diff (relaxed for better detection)

  // Rule-based elbows flaring thresholds
  static const double maxElbowSpreadRatio =
      1.8; // Total elbow spread vs shoulder width
  static const double maxElbowFlareRatio =
      1.4; // Individual elbow-shoulder distance ratio

  // Use portrait 270 like your working BicepCurl page
  InputImageRotation _rotation = InputImageRotation.rotation270deg;

  @override
  void initState() {
    super.initState();

    // Initialize the classifier
    _classifier
        .initialize()
        .then((_) {
          if (mounted) {
            setState(() {
              _classifierReady = true;
              _mlLabel = 'Ready';
            });
          }
          if (kDebugMode) print('[ShoulderPress] ✓ Classifier ready');
        })
        .catchError((e) {
          if (mounted) {
            setState(() {
              _classifierReady = false;
              _mlLabel = 'Model error';
            });
          }
          if (kDebugMode) print('[ShoulderPress] ✗ Classifier init failed: $e');
        });

    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _showInstructionsDialog(),
    );
  }

  @override
  void dispose() {
    _poseDetector.close();
    _classifier.dispose();
    super.dispose();
  }

  // === Camera frame handler ===
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
        if (mounted) {
          setState(() {
            _latestPose = null;
            _feedback = 'No pose detected';
            _postureStatus = 'Tracking...';
            _postureGood = false;
          });
        }
        return;
      }

      _latestPose = poses.first;
      await _analyzePose(_latestPose!);
    } catch (e) {
      if (kDebugMode) print('[ShoulderPress] Exception: $e');
      if (mounted) {
        setState(() {
          _latestPose = null;
          _feedback = 'Error processing frame';
          _postureStatus = 'Tracking...';
          _postureGood = false;
        });
      }
    }
  }

  // YUV420 -> NV21 converter
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

  // Angle calculation using dot product
  double _angle(Offset a, Offset b, Offset c) {
    final ab = a - b;
    final cb = c - b;

    final dot = ab.dx * cb.dx + ab.dy * cb.dy;

    // *** L1 NORM (Manhattan distance) - matches Python ***
    final normAB = ab.dx.abs() + ab.dy.abs();
    final normCB = cb.dx.abs() + cb.dy.abs();
    final denom = (normAB * normCB) + 1e-7;

    if (denom == 0) return 0.0;
    final cosv = (dot / denom).clamp(-1.0, 1.0);
    return (180 / math.pi) * math.acos(cosv);
  }

  // TEST: Feature extractor verification
  void _testFeatureExtractor(Pose pose) {
    final features = ShoulderPressFeatures.computeFeatures(pose);

    if (features == null) {
      if (kDebugMode) print('[Test] Features: null (missing landmarks)');
      return;
    }

    if (kDebugMode) {
      print('╔════════════════════════════════════════════════════════╗');
      print('║  ML Feature Extraction Test                           ║');
      print('╠════════════════════════════════════════════════════════╣');
      print(
        '║  1. left_elbow_angle:          ${features[0].toStringAsFixed(2).padLeft(8)}°  ║',
      );
      print(
        '║  2. right_elbow_angle:         ${features[1].toStringAsFixed(2).padLeft(8)}°  ║',
      );
      print(
        '║  3. shoulder_width:            ${features[2].toStringAsFixed(4).padLeft(8)}   ║',
      );
      print(
        '║  4. wrist_shoulder_diff_left:  ${features[3].toStringAsFixed(4).padLeft(8)}   ║',
      );
      print(
        '║  5. wrist_shoulder_diff_right: ${features[4].toStringAsFixed(4).padLeft(8)}   ║',
      );
      print(
        '║  6. trunk_angle:               ${features[5].toStringAsFixed(2).padLeft(8)}°  ║',
      );
      print(
        '║  7. elbow_angle_diff:          ${features[6].toStringAsFixed(2).padLeft(8)}°  ║',
      );
      print('╚════════════════════════════════════════════════════════╝');
    }
  }

  // TEST: ML Classifier prediction
  Future<void> _testClassifier(Pose pose) async {
    if (!_classifierReady) {
      if (kDebugMode) print('[ML] Classifier not ready yet');
      return;
    }

    try {
      final prediction = await _classifier.predict(pose);

      if (kDebugMode) {
        print('╔════════════════════════════════════════════════════════╗');
        print('║  ML PREDICTION TEST                                    ║');
        print('╠════════════════════════════════════════════════════════╣');
        print('║  Label: ${prediction['label'].toString().padRight(45)} ║');
        print(
          '║  Confidence: ${((prediction['confidence'] as double) * 100).toStringAsFixed(1).padRight(43)}% ║',
        );
        print(
          '║  Good Form: ${(prediction['isGoodForm'] as bool).toString().padRight(43)} ║',
        );
        if (prediction.containsKey('probabilities')) {
          final probs = prediction['probabilities'] as List<double>;
          print(
            '║  Probabilities: ${probs.map((p) => p.toStringAsFixed(3)).join(', ').padRight(37)} ║',
          );
        }
        print('╚════════════════════════════════════════════════════════╝');
      }

      // Update ML state variables
      _mlLabel = prediction['label'] as String;
      _mlConfidence = prediction['confidence'] as double;
      _mlGoodForm = prediction['isGoodForm'] as bool;
    } catch (e) {
      if (kDebugMode) print('[ML] Prediction error: $e');
      _mlLabel = 'Prediction error';
      _mlConfidence = 0.0;
      _mlGoodForm = false;
    }
  }

  // Main pose analysis function
  Future<void> _analyzePose(Pose pose) async {
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

    // ═══ TEST FEATURE EXTRACTION ═══
    _testFeatureExtractor(pose);
    // ═══════════════════════════════

    // ═══ TEST ML PREDICTION ═══
    await _testClassifier(pose);
    // ══════════════════════════

    // Calculate elbow angles (both arms)
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

    // ═══════════════════════════════════════════════════════════════
    // RULE-BASED ELBOWS FLARING DETECTION
    // ═══════════════════════════════════════════════════════════════

    // Calculate body centerline (vertical line between shoulders)
    final shoulderMidX = (ls.x + rs.x) / 2;
    final shoulderWidth = (ls.x - rs.x).abs();

    // Calculate horizontal distance of each elbow from centerline
    _leftElbowFlare = (le.x - shoulderMidX).abs();
    _rightElbowFlare = (re.x - shoulderMidX).abs();

    // Calculate total elbow spread (distance between elbows)
    final elbowSpread = (le.x - re.x).abs();

    // *** CHECK 1: Elbow spread ratio (total width of elbows vs shoulders) ***
    final elbowSpreadRatio = elbowSpread / (shoulderWidth + 1e-7);
    final spreadTooWide = elbowSpreadRatio > maxElbowSpreadRatio;

    // *** CHECK 2: Individual elbow-to-shoulder distance ratio ***
    final leftShoulderDist = math.sqrt(
      math.pow(le.x - ls.x, 2) + math.pow(le.y - ls.y, 2),
    );
    final rightShoulderDist = math.sqrt(
      math.pow(re.x - rs.x, 2) + math.pow(re.y - rs.y, 2),
    );

    // Normalize by shoulder width
    final leftFlareRatio = leftShoulderDist / (shoulderWidth + 1e-7);
    final rightFlareRatio = rightShoulderDist / (shoulderWidth + 1e-7);

    final leftFlaringTooMuch = leftFlareRatio > maxElbowFlareRatio;
    final rightFlaringTooMuch = rightFlareRatio > maxElbowFlareRatio;

    // *** CHECK 3: Asymmetric flaring (one elbow flares more than the other) ***
    final flareDifference = (_leftElbowFlare! - _rightElbowFlare!).abs();
    final asymmetricFlaring =
        flareDifference > (shoulderWidth * 0.3); // 30% of shoulder width

    // *** COMBINED RULE: Elbows are flaring if ANY condition is met ***
    _elbowsFlaringDetected =
        spreadTooWide ||
        leftFlaringTooMuch ||
        rightFlaringTooMuch ||
        asymmetricFlaring;

    // Detailed feedback
    if (_elbowsFlaringDetected) {
      if (spreadTooWide) {
        _flaringDetails =
            'Elbows too wide (${elbowSpreadRatio.toStringAsFixed(2)}x shoulder width)';
      } else if (leftFlaringTooMuch && rightFlaringTooMuch) {
        _flaringDetails = 'Both elbows flaring out';
      } else if (leftFlaringTooMuch) {
        _flaringDetails = 'Left elbow flaring out';
      } else if (rightFlaringTooMuch) {
        _flaringDetails = 'Right elbow flaring out';
      } else if (asymmetricFlaring) {
        _flaringDetails = 'Asymmetric elbow position';
      }
    } else {
      _flaringDetails = 'Elbows in good position';
    }

    if (kDebugMode) {
      print(
        '[Flaring Check] Spread: ${elbowSpreadRatio.toStringAsFixed(2)}x | '
        'L: ${leftFlareRatio.toStringAsFixed(2)}x | '
        'R: ${rightFlareRatio.toStringAsFixed(2)}x | '
        'Flaring: $_elbowsFlaringDetected | $_flaringDetails',
      );
    }

    // *** FIXED: Calculate trunk angle EXACTLY like Python and feature extractor ***
    final midSh = Offset((ls.x + rs.x) / 2, (ls.y + rs.y) / 2);
    final midHp = Offset((lh!.x + rh!.x) / 2, (lh.y + rh.y) / 2);

    // Reference point: horizontal from mid_shoulder (MATCHES PYTHON & ML)
    final refPoint = Offset(midSh.dx + 1.0, midSh.dy);

    // Use 3-point angle function (MATCHES PYTHON & FEATURE EXTRACTOR)
    _trunkAngle = _angle(midHp, midSh, refPoint);

    // Rule-based posture quality checks
    final elbowsDiff = ((_leftElbow ?? 0) - (_rightElbow ?? 0)).abs();

    // *** RANGE-BASED TRUNK CHECK: 80° to 100° is acceptable ***
    // Below 80° = arching back, Above 100° = leaning forward
    final upright =
        _trunkAngle! >= minTorsoAngleDeg && _trunkAngle! <= maxTorsoAngleDeg;

    final symmetric = elbowsDiff < maxAsymmetryDeg;

    // *** UPDATED: Include elbows flaring check in rule-based assessment ***
    final ruleBasedGood = upright && symmetric && !_elbowsFlaringDetected;

    // Debug: Show trunk angle status
    if (kDebugMode) {
      final status =
          _trunkAngle! < minTorsoAngleDeg
              ? 'ARCHING (<$minTorsoAngleDeg°)'
              : (_trunkAngle! > maxTorsoAngleDeg
                  ? 'LEANING (>$maxTorsoAngleDeg°)'
                  : 'UPRIGHT ($minTorsoAngleDeg-$maxTorsoAngleDeg°)');
      print(
        '[Trunk] ${_trunkAngle!.toStringAsFixed(1)}° | Status: $status | Upright: $upright | Symmetric: $symmetric | Flaring: $_elbowsFlaringDetected',
      );
    }

    // *** LABEL-SPECIFIC CONFIDENCE THRESHOLDS ***
    const goodFormThreshold = 0.55; // 55% for Good-Form (lenient)
    const elbowsFlaringThreshold = 0.70; // 65% for Elbows Flaring Out (strict)

    if (_classifierReady) {
      // Determine which threshold to use based on ML prediction label
      final requiredConfidence =
          _mlGoodForm
              ? goodFormThreshold // Good-Form needs 55%+
              : elbowsFlaringThreshold; // Elbows Flaring Out needs 65%+

      if (_mlConfidence >= requiredConfidence) {
        // ═══ CONFIDENCE MEETS LABEL-SPECIFIC THRESHOLD ═══

        if (_mlGoodForm) {
          // ML says Good-Form with 55%+ confidence - accept it
          _postureGood = true;
          _postureStatus =
              'Good Form ✓ (ML: ${(_mlConfidence * 100).toStringAsFixed(1)}%)';

          if (kDebugMode) {
            print(
              '[ML] ✓ Good-Form @ ${(_mlConfidence * 100).toStringAsFixed(1)}% (threshold: 55%)',
            );
          }
        } else {
          // ML says Elbows Flaring Out with 65%+ confidence - accept it
          _postureGood = false;
          _postureStatus =
              'ML: $_mlLabel (${(_mlConfidence * 100).toStringAsFixed(1)}%)';

          if (kDebugMode) {
            print(
              '[ML] ✗ $_mlLabel @ ${(_mlConfidence * 100).toStringAsFixed(1)}% (threshold: 65%)',
            );
          }
        }
      } else {
        // ═══ CONFIDENCE TOO LOW FOR THIS LABEL ═══
        // ML not confident enough - fallback to rule-based
        _postureGood = ruleBasedGood;

        // *** IMPROVED FEEDBACK: Specific trunk angle issue ***
        String ruleFeedback;
        if (!upright) {
          if (_trunkAngle! < minTorsoAngleDeg) {
            ruleFeedback = 'Don\'t arch back'; // < 80° (arching)
          } else {
            ruleFeedback = 'Don\'t lean forward'; // > 100° (leaning)
          }
        } else if (_elbowsFlaringDetected) {
          ruleFeedback = _flaringDetails; // Specific flaring feedback
        } else if (!symmetric) {
          ruleFeedback = 'Keep arms symmetric';
        } else {
          ruleFeedback = 'Good Form ✓ (Rules)';
        }

        _postureStatus = ruleFeedback;

        if (kDebugMode) {
          print(
            '[ML] ⚠️ $_mlLabel @ ${(_mlConfidence * 100).toStringAsFixed(1)}% < ${(requiredConfidence * 100).toStringAsFixed(0)}% threshold - using rules: $ruleBasedGood',
          );
        }
      }
    } else {
      // ML not ready - use rules only
      _postureGood = ruleBasedGood;

      String ruleFeedback;
      if (!upright) {
        if (_trunkAngle! < minTorsoAngleDeg) {
          ruleFeedback = 'Don\'t arch back'; // < 80° (arching)
        } else {
          ruleFeedback = 'Don\'t lean forward'; // > 100° (leaning)
        }
      } else if (_elbowsFlaringDetected) {
        ruleFeedback = _flaringDetails; // Specific flaring feedback
      } else if (!symmetric) {
        ruleFeedback = 'Keep arms symmetric';
      } else {
        ruleFeedback = 'Good Form ✓';
      }

      _postureStatus = ruleFeedback;
    }

    // FSM transitions for rep counting
    if (_state == 'waiting') {
      if (_avgElbow! < loweredThresh) {
        _state = 'lowered';
        _anomaly = false;
      }
    } else if (_state == 'lowered') {
      if (_avgElbow! > raisedThresh) {
        _state = 'raised';

        // *** Only mark anomaly if "Elbows Flaring Out" is detected with 65%+ confidence ***
        if (!_postureGood) {
          if (_classifierReady && !_mlGoodForm && _mlConfidence >= 0.65) {
            // ML confidently detected Elbows Flaring Out
            _anomaly = true;
            if (kDebugMode) {
              print(
                '[Anomaly] ✗ Marked: $_mlLabel @ ${(_mlConfidence * 100).toStringAsFixed(1)}%',
              );
            }
          } else if (!_classifierReady && !ruleBasedGood) {
            // No ML - use rule-based detection
            _anomaly = true;
            if (kDebugMode) print('[Anomaly] ✗ Marked by rules');
          }
        }
      }
    } else if (_state == 'raised') {
      if (_avgElbow! < loweredThresh) {
        if (!_anomaly && _postureGood) {
          _reps += 1;
          _feedback = 'Rep ✓';
        } else {
          _feedback =
              _classifierReady
                  ? 'Fix form: $_mlLabel'
                  : 'Fix form for clean rep';
        }
        _state = 'lowered';
        _anomaly = false;
      }
    }

    // Live feedback based on movement phase
    if (_state == 'lowered' && _avgElbow! < 70) {
      _feedback = _postureGood ? 'Drive up!' : _postureStatus;
    } else if (_state == 'raised' && _avgElbow! > 170) {
      _feedback = _postureGood ? 'Control the descent' : _postureStatus;
    } else if (_feedback != 'Rep ✓' && !_feedback.startsWith('Fix form')) {
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
                  // Camera view
                  CameraWidget(
                    showCamera: _showCamera,
                    onImage: _onCameraImage,
                  ),

                  // Pose overlay painter
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
                          mirror: false,
                        ),
                      ),
                    ),

                  // HUD with metrics and ML predictions
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

                            // ML prediction display
                            if (_classifierReady) ...[
                              const Divider(color: Colors.white24, height: 12),
                              Text(
                                'ML Form: $_mlLabel',
                                style: TextStyle(
                                  color:
                                      _mlGoodForm
                                          ? Colors.greenAccent
                                          : Colors.orangeAccent,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (_mlConfidence > 0)
                                Text(
                                  'Confidence: ${(_mlConfidence * 100).toStringAsFixed(1)}%',
                                  style: const TextStyle(fontSize: 12),
                                ),
                            ],

                            const Divider(color: Colors.white24, height: 12),
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
      final mappedX = size.width - (x * scaleX);
      final mappedY = y * scaleY;
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

    // Draw angle labels
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
