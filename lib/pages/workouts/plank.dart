import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:onnxruntime/onnxruntime.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
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

  // New: whether user pressed Start to allow timer to begin
  bool _userRequestedStart = false;

  // Firebase initialized flag
  bool _firebaseInitialized = false;

  // New: session saved notification flag
  bool _sessionSaved = false;

  // New state fields to hold angles / deviation to display
  double? _bodyAngleDeg;
  double? _segAngleDeg;
  double? _hipDeviationPx;

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
    _initFirebase();
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

  // Initialize Firebase (safe to call even if project hasn't wired deps yet)
  Future<void> _initFirebase() async {
    if (_firebaseInitialized) return;
    try {
      await Firebase.initializeApp();
      // Ensure there's an authenticated user (use anonymous sign-in as fallback)
      try {
        if (FirebaseAuth.instance.currentUser == null) {
          await FirebaseAuth.instance.signInAnonymously();
          if (kDebugMode) print('[FirebaseAuth] signed in anonymously');
        }
      } catch (authErr) {
        if (kDebugMode) print('[FirebaseAuth] sign-in failed: $authErr');
      }
      _firebaseInitialized = true;
      if (kDebugMode) print('[Firebase] initialized');
    } catch (e) {
      if (kDebugMode) print('[Firebase] init failed: $e');
      _firebaseInitialized = false;
    }
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

  // Save session to Firestore collection "plank_sessions"
  Future<bool> _saveSession() async {
    // Ensure Firebase is initialized and we have a user before saving
    if (!_firebaseInitialized) {
      await _initFirebase();
    }
    if (!_firebaseInitialized) {
      if (kDebugMode) print('[Firebase] not initialized, skipping save');
      return false;
    }

    try {
      // Ensure an authenticated user exists (try anonymous sign-in if not)
      User? user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        try {
          final cred = await FirebaseAuth.instance.signInAnonymously();
          user = cred.user;
          if (kDebugMode) {
            print('[FirebaseAuth] signed in anonymously in saveSession');
          }
        } catch (signErr) {
          if (kDebugMode) {
            print('[FirebaseAuth] anonymous sign-in failed: $signErr');
          }
        }
      }

      final userId = user?.uid ?? 'unknown';

      final docRef =
          FirebaseFirestore.instance.collection('plank_sessions').doc();
      await docRef.set({
        'duration': _holdTime.inSeconds,
        'duration_readable': formattedHoldTime,
        'timestamp': FieldValue.serverTimestamp(),
        'userId': userId,
      });
      if (kDebugMode) {
        print('[Firebase] session saved to plank_sessions (${docRef.id})');
      }
      return true;
    } catch (e) {
      if (kDebugMode) print('[Firebase] save failed: $e');
      return false;
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

    // Reset angle values initially
    _bodyAngleDeg = null;
    _segAngleDeg = null;
    _hipDeviationPx = null;

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
      // ensure angles cleared
      _bodyAngleDeg = null;
      _segAngleDeg = null;
      _hipDeviationPx = null;
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

    // store angles/deviation for UI & painter
    _bodyAngleDeg = bodyAngle;
    _segAngleDeg = segAngle;
    _hipDeviationPx = dev;

    if (orientationOk && straightOk && devOk) {
      _feedback = 'Good plank!';
      _goodForm = true;
      // Only start timer if the user explicitly pressed Start
      if (_userRequestedStart) {
        _startTimer();
      } else {
        // waiting for user to press Start
        _stopTimer(reset: true);
        _feedback = 'Good plank! Press Start to begin';
      }
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
      // If the user had requested start, losing good form should PAUSE the timer
      // (do NOT end the session). If user didn't request start, reset timer.
      if (_userRequestedStart) {
        _stopTimer(reset: false); // pause but keep session active
      } else {
        _stopTimer(reset: true);
      }
      _goodForm = false;
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
                break;
              case 1:
                _feedback = 'Hips too high (AI detected)';
                _goodForm = false;
                break;
              case 2:
                _feedback = 'Good plank (AI verified)';
                _goodForm = true;
                break;
              default:
                _feedback = 'Unknown AI output';
                _goodForm = false;
            }
            // Apply same start/pause rules as pose analysis:
            if (_goodForm) {
              if (_userRequestedStart) {
                _startTimer();
              } else {
                _stopTimer(reset: true);
                _feedback = 'Good plank! Press Start to begin';
              }
            } else {
              if (_userRequestedStart) {
                _stopTimer(reset: false); // pause but keep session active
              } else {
                _stopTimer(reset: true);
              }
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

  // Modify stop/start timer to respect user session control
  void _startTimer() {
    // Only allow starting when user requested start and not already holding and good form present
    if (_holding) return;
    if (!_userRequestedStart) return;
    if (!_goodForm) return;
    _holding = true;
    _timer ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (_holding) {
        setState(() => _holdTime += const Duration(seconds: 1));
      }
    });
  }

  // end flag will mark session ended (user must press Start again)
  void _stopTimer({bool reset = false, bool end = false}) {
    if (!_holding) {
      if (reset) setState(() => _holdTime = Duration.zero);
      if (end) {
        _userRequestedStart = false;
      }
      return;
    }
    _holding = false;
    if (reset) setState(() => _holdTime = Duration.zero);
    if (end) {
      _userRequestedStart = false;
      setState(() {
        _feedback = 'Session ended';
      });
    }
  }

  // New: handlers for UI buttons
  void _onStartPressed() {
    if (_userRequestedStart) return;
    setState(() {
      _userRequestedStart = true;
      _feedback = 'Start pressed: waiting for good form';
    });
    // If form already good, attempt to start immediately
    if (_goodForm) {
      _startTimer();
    }
  }

  // make async so we can save to firestore and show notification
  Future<void> _onEndPressed() async {
    _stopTimer(end: true, reset: false);
    final saved = await _saveSession();
    if (saved) {
      setState(() {
        _sessionSaved = true;
        _userRequestedStart = false;
        _feedback = 'Ended by user';
      });
      // clear notification after 3 seconds
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) setState(() => _sessionSaved = false);
      });
    } else {
      setState(() {
        _userRequestedStart = false;
        _feedback = 'Ended by user (save failed)';
      });
    }
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
          // ignore: deprecated_member_use
          (_) => WillPopScope(
            onWillPop: () async => false, // disable system/back button
            child: Dialog(
              // ignore: deprecated_member_use
              backgroundColor: Theme.of(context).dialogBackgroundColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8.0),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: IntrinsicHeight(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Plank Instructions',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Flexible(
                        child: SingleChildScrollView(
                          child: Text(
                            '1) Get into plank position (side view, elbows or hands).\n'
                            '2) Keep a straight line from shoulders to heels.\n'
                            '3) Ensure the camera sees your full side body.\n'
                            '4) The timer runs only when posture is correct.',
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Align(
                        alignment: Alignment.centerRight,
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(context),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.purple,
                          ),
                          child: const Text('Start'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
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
                          bodyAngleDeg: _bodyAngleDeg,
                          segAngleDeg: _segAngleDeg,
                        ),
                      ),
                    ),
                  // CENTER: Start / End buttons
                  Positioned.fill(
                    child: IgnorePointer(
                      ignoring: false,
                      child: Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ElevatedButton(
                              onPressed:
                                  _userRequestedStart ? null : _onStartPressed,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green.withValues(
                                  alpha: 0.12,
                                ),
                                foregroundColor: Colors.greenAccent,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 12,
                                ),
                              ),
                              child: const Text('Start'),
                            ),
                            const SizedBox(width: 16),
                            ElevatedButton(
                              onPressed:
                                  (_userRequestedStart || _holding)
                                      ? _onEndPressed
                                      : null,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red.withValues(
                                  alpha: 0.12,
                                ),
                                foregroundColor: Colors.redAccent,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 12,
                                ),
                              ),
                              child: const Text('End'),
                            ),
                          ],
                        ),
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
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // LEFT SIDE: hold time + feedback
                            Column(
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

                            // RIGHT SIDE: angles info
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  'Hip angle: ${_bodyAngleDeg != null ? "${_bodyAngleDeg!.toStringAsFixed(1)}°" : "-"}',
                                  style: const TextStyle(fontSize: 14),
                                ),
                                Text(
                                  'Orientation: ${_segAngleDeg != null ? "${_segAngleDeg!.toStringAsFixed(1)}°" : "-"}',
                                  style: const TextStyle(fontSize: 14),
                                ),
                                Text(
                                  'Hip dev: ${_hipDeviationPx != null ? _hipDeviationPx!.toStringAsFixed(1) : "-"} px',
                                  style: const TextStyle(fontSize: 14),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // NOTIFICATION: show small message below the bottom HUD when session saved
                  if (_sessionSaved)
                    Positioned(
                      bottom: 8,
                      left: 16,
                      right: 16,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            vertical: 6,
                            horizontal: 12,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black87,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Colors.greenAccent,
                              width: 1.5,
                            ),
                          ),
                          child: const Text(
                            'Session saved.',
                            style: TextStyle(
                              color: Colors.greenAccent,
                              fontWeight: FontWeight.bold,
                            ),
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

  // new fields to receive angle values
  final double? bodyAngleDeg;
  final double? segAngleDeg;

  _PlankPainter({
    required this.pose,
    required this.imageWidth,
    required this.imageHeight,
    required this.postureGood,
    required this.rotation,
    this.bodyAngleDeg,
    this.segAngleDeg,
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

    // Draw angle text close to hip center if available
    Offset? hipCenter;
    final lHip = lm[PoseLandmarkType.leftHip];
    final rHip = lm[PoseLandmarkType.rightHip];
    if (lHip != null && rHip != null) {
      hipCenter = Offset((lHip.x + rHip.x) / 2.0, (lHip.y + rHip.y) / 2.0);
    } else if (lHip != null) {
      hipCenter = Offset(lHip.x, lHip.y);
    } else if (rHip != null) {
      hipCenter = Offset(rHip.x, rHip.y);
    }

    if (hipCenter != null && (bodyAngleDeg != null || segAngleDeg != null)) {
      final pos = map(hipCenter.dx, hipCenter.dy);
      final textStyle = TextStyle(
        color: postureGood ? Colors.greenAccent : Colors.orangeAccent,
        fontSize: 12,
        fontWeight: FontWeight.bold,
      );

      final angleLines = <String>[];
      if (bodyAngleDeg != null) {
        angleLines.add('Hip: ${bodyAngleDeg!.toStringAsFixed(1)}°');
      }
      if (segAngleDeg != null) {
        angleLines.add('Orient: ${segAngleDeg!.toStringAsFixed(1)}°');
      }

      final tp = TextPainter(
        text: TextSpan(
          children:
              angleLines
                  .map((s) => TextSpan(text: '$s\n', style: textStyle))
                  .toList(),
        ),
        textAlign: TextAlign.left,
        textDirection: TextDirection.ltr,
      )..layout();

      // draw background for readability
      final bgRect = Rect.fromLTWH(
        pos.dx + 8,
        pos.dy - tp.height / 2 - 6,
        tp.width + 8,
        tp.height + 8,
      );
      final bgPaint = Paint()..color = Colors.black54;
      canvas.drawRRect(
        RRect.fromRectAndRadius(bgRect, const Radius.circular(6)),
        bgPaint,
      );

      tp.paint(canvas, Offset(pos.dx + 12, pos.dy - tp.height / 2 - 2));
    }
  }

  @override
  bool shouldRepaint(covariant _PlankPainter old) =>
      old.pose != pose ||
      old.postureGood != postureGood ||
      old.bodyAngleDeg != bodyAngleDeg ||
      old.segAngleDeg != segAngleDeg;
}
