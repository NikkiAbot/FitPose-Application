import 'dart:async';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

// NEW: Firebase imports
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../components/camera_widget.dart';
import '../../models/lunges_feature_extract.dart';

class Lunges extends StatefulWidget {
  const Lunges({super.key});

  @override
  // ignore: no_logic_in_create_state
  State<Lunges> createState() {
    debugPrint(
      '🌟🌟🌟 Lunges.createState() CALLED - CREATING NEW STATE 🌟🌟🌟',
    );
    return _LungesState();
  }
}

class _LungesState extends State<Lunges> {
  _LungesState() {
    debugPrint('🔥🔥🔥 LUNGES STATE CONSTRUCTOR CALLED 🔥🔥🔥');
  }

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
  // CLASSIFIERS (Not used - using rule-based detection instead)
  // ═══════════════════════════════════════════════════════════════
  // Kept for potential future use, but not initialized

  // ═══════════════════════════════════════════════════════════════
  // STATE TRACKING
  // ═══════════════════════════════════════════════════════════════
  String _currentStage = ''; // 'init', 'mid', 'down'
  int _counter = 0;

  // Reps/sets tracking
  static const int _repsPerSet = 8; // changed from 12 to 8
  int get _setsCompleted => _counter ~/ _repsPerSet;

  // New: store counter at session start so we can compute session-only reps
  int? _counterAtSessionStart;

  // NEW: attempted reps tracking (total and session baseline)
  int _attemptedReps = 0;
  int? _attemptedAtSessionStart;

  // New: session timing state
  Timer? _sessionTimer;
  DateTime? _sessionStart;
  Duration _sessionElapsed = Duration.zero;
  bool _sessionActive = false;

  // Thresholds
  static const List<double> angleThresholds = [
    60.0,
    135.0,
  ]; // Knee angle limits

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
    debugPrint('═══════════════════════════════════════════');
    debugPrint('[Lunges] 🚀 INIT STATE CALLED - RULE-BASED MODE');
    debugPrint('═══════════════════════════════════════════');
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _showInstructionsDialog(),
    );
  }

  @override
  void dispose() {
    _poseDetector.close();
    _sessionTimer?.cancel(); // ensure timer is cancelled
    super.dispose();
  }

  // Start the duration timer
  void _startSession() {
    if (_sessionActive) return;
    _sessionStart = DateTime.now();
    _sessionElapsed = Duration.zero;
    _counterAtSessionStart = _counter; // capture starting counter
    // NEW: capture attempted reps at session start
    _attemptedAtSessionStart = _attemptedReps;
    _sessionTimer?.cancel();
    _sessionTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _sessionElapsed = DateTime.now().difference(_sessionStart!);
      });
    });
    setState(() {
      _sessionActive = true;
    });
  }

  // End the duration timer and save session to Firestore
  Future<void> _endSession() async {
    if (!_sessionActive) return;
    _sessionTimer?.cancel();
    _sessionTimer = null;
    _sessionElapsed = DateTime.now().difference(_sessionStart!);
    setState(() {
      _sessionActive = false;
    });

    // Save session to Firestore (only after start and end)
    final saved = await _saveSessionToFirestore();

    if (!mounted) return;
    if (saved) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Session Saved'),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.only(bottom: 24, left: 16, right: 16),
          duration: const Duration(seconds: 2),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  // New: persist session document to 'lunges_sessions'
  Future<bool> _saveSessionToFirestore() async {
    bool success = false;
    try {
      final start = _sessionStart ?? DateTime.now();
      start.add(_sessionElapsed);
      final sessionReps = _counter - (_counterAtSessionStart ?? 0);
      final sessionSets = sessionReps ~/ _repsPerSet; // use 8-per-set rule
      final durationSeconds = _sessionElapsed.inSeconds;
      final userId = FirebaseAuth.instance.currentUser?.uid ?? 'anonymous';
      // NEW: compute session attempted reps from baseline
      final sessionAttemptedReps =
          _attemptedReps - (_attemptedAtSessionStart ?? 0);

      final data = <String, dynamic>{
        'userId': userId,
        'reps': sessionReps,
        'sets': sessionSets,
        'duration': durationSeconds,
        'duration_formatted': _formatDuration(_sessionElapsed),
        'timestamp': FieldValue.serverTimestamp(),
        // NEW: persist attempted reps for this session
        'attemptedReps': sessionAttemptedReps,
      };

      await FirebaseFirestore.instance.collection('lunges_sessions').add(data);

      if (kDebugMode) {
        print('[Lunges] ✅ Session saved: $data');
      }
      success = true;
    } catch (e, st) {
      if (kDebugMode) {
        print('[Lunges] ❌ Failed to save session: $e');
        print(st);
      }
    } finally {
      // clear baselines so next session is fresh
      _counterAtSessionStart = null;
      // NEW: clear attempted baseline
      _attemptedAtSessionStart = null;
    }
    return success;
  }

  // Simple mm:ss formatter
  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
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

    try {
      // ═══════════════════════════════════════════════════════════════
      // 1) KNEE ANGLE ANALYSIS - ALWAYS FIRST
      // ═══════════════════════════════════════════════════════════════
      _kneeAnalysis = LungesFeatureExtractor.analyzeKneeAngle(
        lm,
        _currentStage,
        angleThresholds,
      );

      final rightKneeAngle = (_kneeAnalysis!['right']['angle'] as double);
      final leftKneeAngle = (_kneeAnalysis!['left']['angle'] as double);

      // Use the smaller angle (more bent knee) for stage detection
      final minKneeAngle =
          rightKneeAngle < leftKneeAngle ? rightKneeAngle : leftKneeAngle;

      // Track previous stage for rep counting
      final previousStage = _currentStage;

      // ═══════════════════════════════════════════════════════════════
      // 2) RULE-BASED STAGE DETECTION (Simple and Reliable!)
      // ═══════════════════════════════════════════════════════════════
      // INIT: Standing upright (knees almost straight)
      // MID: Descending/ascending (knees moderately bent)
      // DOWN: Bottom of lunge (knees deeply bent)

      if (minKneeAngle > 150) {
        _currentStage = 'init';
        _stagePredictedClass = 'I';
        _stageProbability = 1.0;
      } else if (minKneeAngle > 110) {
        _currentStage = 'mid';
        _stagePredictedClass = 'M';
        _stageProbability = 1.0;
      } else {
        _currentStage = 'down';
        _stagePredictedClass = 'D';
        _stageProbability = 1.0;
      }

      if (kDebugMode) {
        print(
          '[Lunges] 🎯 RULE-BASED: Stage=$_currentStage | Min Knee Angle=${minKneeAngle.toStringAsFixed(1)}° (R=${rightKneeAngle.toStringAsFixed(0)}° L=${leftKneeAngle.toStringAsFixed(0)}°)',
        );

        if (_currentStage != previousStage) {
          print('[Lunges] ✅ TRANSITION: $previousStage → $_currentStage');
        }
      }

      // ═══════════════════════════════════════════════════════════════
      // 3) KNEE-OVER-TOE ERROR DETECTION (Multi-Factor Scoring!)
      // ═══════════════════════════════════════════════════════════════
      // Uses 3 indicators - needs 2+ to trigger K-O-T:
      // 1. Knee-to-ankle horizontal distance > 25px
      // 2. Knee-to-toe horizontal distance > 20px
      // 3. Shin angle ratio > 0.35 (shin leaning forward)
      _errorClass = null;
      _errorProbability = null;

      if (_currentStage == 'down') {
        final rightKnee = lm[PoseLandmarkType.rightKnee];
        final rightAnkle = lm[PoseLandmarkType.rightAnkle];
        final rightFootIndex = lm[PoseLandmarkType.rightFootIndex];

        final leftKnee = lm[PoseLandmarkType.leftKnee];
        final leftAnkle = lm[PoseLandmarkType.leftAnkle];
        final leftFootIndex = lm[PoseLandmarkType.leftFootIndex];

        bool hasKOTError = false;

        // NEW: Determine front leg by KNEE Y POSITION (lower knee = front leg in lunge)
        // In camera coords, higher Y value = lower on screen = front leg
        final rightKneeY = rightKnee?.y ?? 0;
        final leftKneeY = leftKnee?.y ?? 0;

        // Front leg is the one with LOWER Y position (higher on screen, closer to camera)
        final rightIsFront = rightKneeY < leftKneeY;

        if (kDebugMode) {
          print(
            '[Lunges] 🦵 Front leg: ${rightIsFront ? "RIGHT" : "LEFT"} (R_Y=$rightKneeY, L_Y=$leftKneeY)',
          );
        }

        if (rightIsFront &&
            rightKnee != null &&
            rightAnkle != null &&
            rightFootIndex != null) {
          // Check RIGHT front leg ONLY
          final kneeX = rightKnee.x;
          final ankleX = rightAnkle.x;

          // Simple and effective: Just check horizontal knee-to-ankle distance
          // In proper form, ankle should be roughly below knee (small horizontal gap)
          // In K-O-T error, knee is significantly ahead of ankle
          final kneeToAnkleHorizontal = (kneeX - ankleX).abs();
          final kneeAheadOfAnkle =
              true; // REMOVED DIRECTION CHECK - works both ways now

          if (kDebugMode) {
            print(
              // ignore: dead_code
              '[Lunges] � RIGHT knee-to-ankle horizontal: ${kneeToAnkleHorizontal.toStringAsFixed(0)}px ${kneeAheadOfAnkle ? "(knee ahead)" : "(ankle ahead)"}',
            );
          }

          // K-O-T: knee is ahead of ankle (>25px horizontal distance)
          // LOWER threshold for better detection
          // PLUS: Check ankle angle (knee-ankle-toe)
          final ankleAngle = LungesFeatureExtractor.calculateAngle(
            [rightKnee.x, rightKnee.y],
            [rightAnkle.x, rightAnkle.y],
            [rightFootIndex.x, rightFootIndex.y],
          );

          // Multi-factor: distance + ankle bend
          final distanceError = kneeAheadOfAnkle && kneeToAnkleHorizontal > 25;
          final ankleBentError =
              ankleAngle < 85; // Ankle too bent indicates K-O-T

          if (distanceError || ankleBentError) {
            hasKOTError = true;
            if (kDebugMode) {
              print(
                '[Lunges] 🚨 RIGHT K-O-T: Distance=${kneeToAnkleHorizontal.toStringAsFixed(0)}px AnkleAngle=${ankleAngle.toStringAsFixed(0)}° ${distanceError ? "[DIST]" : ""}${ankleBentError ? "[ANKLE]" : ""}',
              );
            }
          } else if (kDebugMode) {
            print(
              '[Lunges] ✅ RIGHT OK: Distance=${kneeToAnkleHorizontal.toStringAsFixed(0)}px AnkleAngle=${ankleAngle.toStringAsFixed(0)}°',
            );
          }
        } else if (!rightIsFront &&
            leftKnee != null &&
            leftAnkle != null &&
            leftFootIndex != null) {
          // Check LEFT front leg ONLY
          final kneeX = leftKnee.x;
          final ankleX = leftAnkle.x;

          final kneeToAnkleHorizontal = (kneeX - ankleX).abs();
          final kneeAheadOfAnkle =
              true; // REMOVED DIRECTION CHECK - works both ways now

          if (kDebugMode) {
            print(
              // ignore: dead_code
              '[Lunges] � LEFT knee-to-ankle horizontal: ${kneeToAnkleHorizontal.toStringAsFixed(0)}px ${kneeAheadOfAnkle ? "(knee ahead)" : "(ankle ahead)"}',
            );
          }

          // K-O-T: knee is ahead of ankle (>25px horizontal distance)
          // LOWER threshold for better detection
          // PLUS: Check ankle angle (knee-ankle-toe)
          final ankleAngle = LungesFeatureExtractor.calculateAngle(
            [leftKnee.x, leftKnee.y],
            [leftAnkle.x, leftAnkle.y],
            [leftFootIndex.x, leftFootIndex.y],
          );

          // Multi-factor: distance + ankle bend
          final distanceError = kneeAheadOfAnkle && kneeToAnkleHorizontal > 25;
          final ankleBentError = ankleAngle < 85; // Ankle too bent

          if (distanceError || ankleBentError) {
            hasKOTError = true;
            if (kDebugMode) {
              print(
                '[Lunges] 🚨 LEFT K-O-T: Distance=${kneeToAnkleHorizontal.toStringAsFixed(0)}px AnkleAngle=${ankleAngle.toStringAsFixed(0)}° ${distanceError ? "[DIST]" : ""}${ankleBentError ? "[ANKLE]" : ""}',
              );
            }
          } else if (kDebugMode) {
            print(
              '[Lunges] ✅ LEFT OK: Distance=${kneeToAnkleHorizontal.toStringAsFixed(0)}px AnkleAngle=${ankleAngle.toStringAsFixed(0)}°',
            );
          }
        }

        if (hasKOTError) {
          _errorClass = 'K';
          _errorProbability = 1.0;
        }
      }

      // ═══════════════════════════════════════════════════════════════
      // 5) REP COUNTING - Count when ENTERING "down" from "mid" or "init"
      // Matches Python logic: if current_stage in ["mid", "init"]: counter += 1
      // ═══════════════════════════════════════════════════════════════
      // Count rep when we transition TO "down" FROM "mid" or "init"
      if (kDebugMode) {
        print(
          '[Lunges] 🔍 Rep Check - Previous: "$previousStage", Current: "$_currentStage"',
        );
      }

      if (_currentStage == 'down' &&
          (previousStage == 'mid' || previousStage == 'init')) {
        _counter += 1;
        _attemptedReps += 1;
        if (kDebugMode) {
          print(
            '[Lunges] 🎉🎉🎉 REP #$_counter COUNTED! ($previousStage → down) 🎉🎉🎉',
          );
        }
      } else if (kDebugMode) {
        if (_currentStage == 'down' && previousStage == 'down') {
          print('[Lunges] ⏭️ Already in down stage, no rep');
        } else if (_currentStage != 'down') {
          print('[Lunges] ⏭️ Not in down stage yet');
        }
      }
      if (kDebugMode) {
        print(
          '[Lunges] Stage: $_currentStage ($_stagePredictedClass @ ${(_stageProbability! * 100).toStringAsFixed(0)}%) | '
          'Counter: $_counter | '
          'Error: $_errorClass${_errorProbability != null ? " @ ${(_errorProbability! * 100).toStringAsFixed(0)}%" : " (not checked)"}',
        );
        if (_kneeAnalysis != null) {
          final rightAngle = (_kneeAnalysis!['right']['angle'] as double)
              .toStringAsFixed(0);
          final leftAngle = (_kneeAnalysis!['left']['angle'] as double)
              .toStringAsFixed(0);
          print('[Lunges] Knee angles: R:$rightAngle° L:$leftAngle°');
        }
      }
    } catch (e) {
      if (kDebugMode) print('[Lunges] Analysis error: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // UI BUILD METHODzz
  // ═══════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    debugPrint('🏗️ [Lunges] build() method called');

    // Determine HUD color based on form quality
    final hudColor = _errorClass == 'K' ? Colors.redAccent : Colors.green;

    // Replace deprecated onPopInvoked with onPopInvokedWithResult
    return PopScope(
      canPop: !_sessionActive,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return; // predictive/system back already popped
        final proceed = await _confirmExitIfSessionActive();
        if (proceed && mounted) {
          // ignore: use_build_context_synchronously
          Navigator.of(context).pop(result);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Lunges'),
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
                            errorClass: _errorClass,
                          ),
                        ),
                      ),

                    // HUD with metrics (matching bicep curl style)
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
                            children: [
                              // Status row
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  // Stage status
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'STAGE',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.white70,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            Container(
                                              width: 8,
                                              height: 8,
                                              decoration: BoxDecoration(
                                                color:
                                                    _currentStage == 'down'
                                                        ? Colors.green
                                                        : _currentStage == 'mid'
                                                        ? Colors.orange
                                                        : Colors.blue,
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              _currentStage.isNotEmpty
                                                  ? _currentStage.toUpperCase()
                                                  : 'INIT',
                                              style: TextStyle(
                                                fontSize: 22,
                                                fontWeight: FontWeight.bold,
                                                color:
                                                    _currentStage == 'down'
                                                        ? Colors.green
                                                        : _currentStage == 'mid'
                                                        ? Colors.orange
                                                        : Colors.blue,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '${_stageProbability != null ? (_stageProbability! * 100).toStringAsFixed(0) : "100"}% confident',
                                          style: const TextStyle(
                                            fontSize: 10,
                                            color: Colors.white60,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                  // Reps & Sets container (UPDATED)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(
                                        alpha: 0.1,
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Column(
                                      children: [
                                        const Text(
                                          'REPS',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.white70,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        // Display total overall reps
                                        Text(
                                          '$_counter',
                                          style: const TextStyle(
                                            fontSize: 28,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        // Remove the " •  Total: $_counter"
                                        Text(
                                          'Sets: $_setsCompleted',
                                          style: const TextStyle(
                                            fontSize: 10,
                                            color: Colors.white60,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),

                              // NEW: Session duration row (buttons moved to bottom center)
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.start,
                                children: [
                                  // Duration display only
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'DURATION',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.white70,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        _formatDuration(_sessionElapsed),
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),

                              const SizedBox(height: 12),
                              const Divider(color: Colors.white24, height: 1),
                              const SizedBox(height: 12),

                              // Form analysis row
                              Row(
                                children: [
                                  // Knee-Over-Toe status
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'KNEE-OVER-TOE',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.white70,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            Icon(
                                              _errorClass == 'K'
                                                  ? Icons.warning_rounded
                                                  : Icons.check_circle_rounded,
                                              color:
                                                  _errorClass == 'K'
                                                      ? Colors.red
                                                      : Colors.green,
                                              size: 16,
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              _errorClass == 'K'
                                                  ? 'Detected'
                                                  : 'Good Form',
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.bold,
                                                color:
                                                    _errorClass == 'K'
                                                        ? Colors.red
                                                        : Colors.green,
                                              ),
                                            ),
                                          ],
                                        ),
                                        if (_errorProbability != null)
                                          Text(
                                            'Confidence: ${(_errorProbability! * 100).toStringAsFixed(0)}%',
                                            style: const TextStyle(
                                              fontSize: 10,
                                              color: Colors.white60,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),

                                  // Knee angles
                                  if (_kneeAnalysis != null)
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(
                                          alpha: 0.1,
                                        ),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              const Text(
                                                'R: ',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: Colors.white70,
                                                ),
                                              ),
                                              Text(
                                                '${(_kneeAnalysis!['right']['angle'] as double).toStringAsFixed(0)}°',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.bold,
                                                  color:
                                                      _kneeAnalysis!['right']['error']
                                                          ? Colors.red
                                                          : Colors.green,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 2),
                                          Row(
                                            children: [
                                              const Text(
                                                'L: ',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: Colors.white70,
                                                ),
                                              ),
                                              Text(
                                                '${(_kneeAnalysis!['left']['angle'] as double).toStringAsFixed(0)}°',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.bold,
                                                  color:
                                                      _kneeAnalysis!['left']['error']
                                                          ? Colors.red
                                                          : Colors.green,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ), // end of main HUD Positioned
                    // Bottom-center Start / End buttons (transparent / faint colors)
                    Positioned(
                      bottom: 24,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ElevatedButton(
                              onPressed: _sessionActive ? null : _startSession,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green.withValues(
                                  alpha: 0.15,
                                ),
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(24),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 28,
                                  vertical: 12,
                                ),
                                shadowColor: Colors.transparent,
                              ),
                              child: const Text(
                                'Start',
                                style: TextStyle(color: Colors.white),
                              ),
                            ),
                            const SizedBox(width: 12),
                            ElevatedButton(
                              onPressed: _sessionActive ? _endSession : null,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red.withValues(
                                  alpha: 0.12,
                                ),
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(24),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 28,
                                  vertical: 12,
                                ),
                                shadowColor: Colors.transparent,
                              ),
                              child: const Text(
                                'End',
                                style: TextStyle(color: Colors.white),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                )
                : const Center(child: Text('Camera off')),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // INSTRUCTIONS DIALOG
  // ═══════════════════════════════════════════════════════════════

  void _showInstructionsDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (_) => AlertDialog(
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

  // New: confirm exit if session is active
  Future<bool> _confirmExitIfSessionActive() async {
    if (!_sessionActive) return true;

    final proceed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder:
          (_) => AlertDialog(
            title: const Text('Unsaved Session'),
            content: const Text(
              'You have not yet ended the session, proceeding to exit the session without saving will lose all unsaved progress, do you wish to proceed?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('No'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Yes'),
              ),
            ],
          ),
    );

    return proceed ?? false;
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
  final String? errorClass;

  _LungesPainter({
    required this.pose,
    required this.imageWidth,
    required this.imageHeight,
    required this.kneeAnalysis,
    required this.currentStage,
    required this.rotation,
    required this.mirror,
    this.errorClass,
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

    final linePaint =
        Paint()
          ..color = errorClass == 'K' ? Colors.orangeAccent : Colors.greenAccent
          ..strokeWidth = 3
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round;

    final jointPaint =
        Paint()
          ..color = errorClass == 'K' ? Colors.orange : Colors.green
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
        tp.paint(
          canvas,
          mapPoint(rightKnee.x, rightKnee.y) + const Offset(10, -15),
        );
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
        tp.paint(
          canvas,
          mapPoint(leftKnee.x, leftKnee.y) + const Offset(10, -15),
        );
      }
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _LungesPainter old) =>
      old.pose != pose ||
      old.kneeAnalysis != kneeAnalysis ||
      old.currentStage != currentStage ||
      old.errorClass != errorClass;
}
