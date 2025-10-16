import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
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

  @override
  void initState() {
    super.initState();
    // Lock app orientation to landscape
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _showInstructionsDialog(),
    );
  }

  @override
  void dispose() {
    _poseDetector.close();
    _timer?.cancel();
    // Restore portrait when leaving page
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    super.dispose();
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

    final ls = lm[PoseLandmarkType.leftShoulder];
    final rs = lm[PoseLandmarkType.rightShoulder];
    final lh = lm[PoseLandmarkType.leftHip];
    final rh = lm[PoseLandmarkType.rightHip];
    final la = lm[PoseLandmarkType.leftAnkle];
    final ra = lm[PoseLandmarkType.rightAnkle];
    final le = lm[PoseLandmarkType.leftElbow];
    final re = lm[PoseLandmarkType.rightElbow];
    final lw = lm[PoseLandmarkType.leftWrist];
    final rw = lm[PoseLandmarkType.rightWrist];

    if ([ls, rs, lh, rh, la, ra, le, re, lw, rw].any((p) => p == null)) {
      _feedback = 'Move fully into view';
      _goodForm = false;
      _stopTimer();
      return;
    }

    final midShoulder = Offset((ls!.x + rs!.x) / 2, (ls.y + rs.y) / 2);
    final midHip = Offset((lh!.x + rh!.x) / 2, (lh.y + rh.y) / 2);
    final midAnkle = Offset((la!.x + ra!.x) / 2, (la.y + ra.y) / 2);
    final midElbow = Offset((le!.x + re!.x) / 2, (le.y + re.y) / 2);
    final midWrist = Offset((lw!.x + rw!.x) / 2, (lw.y + rw.y) / 2);

    const maxTorsoDeviation = 20; // pixels
    const maxLegDeviation = 20;

    final torsoDeltaY = (midShoulder.dy - midHip.dy);
    final legDeltaY = (midHip.dy - midAnkle.dy).abs();

    final armsDown =
        (midElbow.dy > midShoulder.dy) && (midWrist.dy > midShoulder.dy);
    final torsoStraight = torsoDeltaY.abs() < maxTorsoDeviation;
    final legsStraight = legDeltaY < maxLegDeviation;

    bool hipsTooHigh = torsoDeltaY < -maxTorsoDeviation;
    bool hipsTooLow = torsoDeltaY > maxTorsoDeviation;

    _goodForm = torsoStraight && legsStraight && armsDown;

    if (_goodForm) {
      _feedback = 'Hold that plank!';
      _startTimer();
    } else {
      if (!armsDown) {
        _feedback = 'Keep your arms on the floor';
      } else if (!torsoStraight) {
        if (hipsTooHigh) {
          _feedback = 'Hips too high';
        } else if (hipsTooLow)
          _feedback = 'Hips too low';
        else
          _feedback = 'Keep your back straight';
      } else if (!legsStraight) {
        _feedback = 'Keep your legs straight';
      } else {
        _feedback = 'Adjust your plank';
      }
      _stopTimer();
    }
  }

  void _startTimer() {
    if (_holding) return;
    _holding = true;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _holdTime += const Duration(seconds: 1));
    });
  }

  void _stopTimer() {
    if (!_holding) return;
    _holding = false;
    _timer?.cancel();
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
              '1) Get into plank position (elbows or hands).\n'
              '2) Keep a straight line from shoulders to heels.\n'
              '3) Avoid sagging or arching your back.\n'
              '4) The app will track your posture and hold time.',
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
