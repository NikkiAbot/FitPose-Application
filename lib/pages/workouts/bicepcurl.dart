import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:onnxruntime/onnxruntime.dart' as ort;
import 'package:path_provider/path_provider.dart';

import '../../components/camera_widget.dart';

class BicepCurl extends StatefulWidget {
  const BicepCurl({super.key});
  @override
  State<BicepCurl> createState() => _BicepCurlState();
}

class _BicepCurlState extends State<BicepCurl> {
  // Camera rotation captured from CameraWidget

  // Show/hide camera widget
  bool showCamera = true;
  bool mirrorOverlay = true; // selfie-style overlay by default

  // Window size for smoothing buffers
  static const int _windowSize = 5;

  // Models
  late final PoseDetector _pose;
  ort.OrtSession? _knn;
  late List<String> _labels;
  bool _modelsReady = false;

  // Buffers
  final _dx = ListQueue<double>(_windowSize);
  final _incl = ListQueue<double>(_windowSize);
  final _ang = ListQueue<double>(_windowSize);
  final _vel = ListQueue<double>(_windowSize);
  final _wh = ListQueue<double>(_windowSize);
  final _mc = ListQueue<double>(_windowSize);
  final _rom = ListQueue<double>(_windowSize);

  // FSM + counters
  String state = "extended";
  bool cycleOk = false;
  int reps = 0;

  double? _prevAng;
  int? _prevTms;

  // UI
  String instruction = "";
  String formLabel = "neutral";
  Pose? lastPose;
  Size? _imageSize;

  // Auto-rotation probe for ML Kit
  InputImageRotation _mlkitRotation = InputImageRotation.rotation0deg;
  int _noDetectFrames = 0;
  bool _rotationLocked = false;

  // processing guard
  bool _processing = false;

  @override
  void initState() {
    super.initState();
    _initModels();
    // Show how-to dialog on first open
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _showInstructionsDialog(),
    );
  }

  @override
  void dispose() {
    // CameraWidget handles camera cleanup itself
    unawaited(_pose.close());
    _knn = null;
    super.dispose();
  }

  Future<void> _initModels() async {
    try {
      debugPrint('[BicepCurl] Init models start');

      // Pose detector
      _pose = PoseDetector(
        options: PoseDetectorOptions(mode: PoseDetectionMode.stream),
      );
      debugPrint('[BicepCurl] PoseDetector ready');

      // ONNX: load asset and verify bytes
      const onnxPath = 'assets/form_knn.onnx';
      final bd = await rootBundle.load(onnxPath);
      debugPrint(
        '[BicepCurl] ONNX asset ByteData lengthInBytes=${bd.lengthInBytes}',
      );
      final bytes = bd.buffer.asUint8List(bd.offsetInBytes, bd.lengthInBytes);
      debugPrint('[BicepCurl] ONNX Uint8List length=${bytes.length}');
      if (bytes.isEmpty) {
        throw Exception('ONNX bytes are empty after slice');
      }

      // Choose a stable writable dir
      final supportDir = await getApplicationSupportDirectory();
      debugPrint('[BicepCurl] Support dir: ${supportDir.path}');
      await supportDir.create(recursive: true);
      final modelFile = File('${supportDir.path}/form_knn.onnx');

      // Always overwrite (avoid 0-byte reuse)
      await modelFile.writeAsBytes(bytes, flush: true);

      final written = await modelFile.length();
      debugPrint('[BicepCurl] Wrote model bytes=$written -> ${modelFile.path}');
      if (written == 0) {
        throw Exception('Wrote 0 bytes to ${modelFile.path}');
      }

      // Create OrtSession (onnxruntime is sync)
      _knn = ort.OrtSession.fromFile(modelFile, ort.OrtSessionOptions());
      debugPrint('[BicepCurl] OrtSession created');
      try {
        debugPrint('[BicepCurl] Session inputs=${_knn!.inputNames}');
        debugPrint('[BicepCurl] Session outputs=${_knn!.outputNames}');
      } catch (_) {
        // some builds may not expose names until run; ignore
      }

      // Labels: load and verify
      const labelsPath = 'assets/form_labels.json';
      final lblText = await rootBundle.loadString(labelsPath);
      debugPrint('[BicepCurl] Labels raw chars=${lblText.length}');
      if (lblText.trim().isEmpty) {
        throw Exception('assets/form_labels.json is empty');
      }
      _labels = List<String>.from(json.decode(lblText));
      debugPrint('[BicepCurl] Labels parsed count=${_labels.length}');

      if (mounted) setState(() => _modelsReady = true);
      debugPrint('[BicepCurl] Init models done');
    } catch (e, st) {
      debugPrint('[BicepCurl] Model init error: $e (${e.runtimeType})');
      debugPrint('$st');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to load models: $e')));
      }
    }
  }

  void _showInstructionsDialog() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder:
          (_) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.fitness_center, color: Colors.blue, size: 28),
                SizedBox(width: 8),
                Text(
                  'Bicep Curl Exercise',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            content: const Text(
              '1) Stand feet shoulder-width apart\n'
              '2) Keep elbows close to body\n'
              '3) Curl up, then lower under control',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Start'),
              ),
            ],
          ),
    );
  }

  // 👇 updated callback signature: receives rotationDegrees from CameraWidget
  Future<void> _onImage(
    CameraImage img,
    int rotationDegrees, {
    required bool mirror,
    required InputImageRotation rotation,
  }) async {
    if (!_modelsReady || _processing) return;
    _processing = true;

    try {
      _imageSize = Size(img.width.toDouble(), img.height.toDouble());

      // Seed rotation from camera (if provided) until we lock a good one
      if (!_rotationLocked) {
        _mlkitRotation = _rotationFromDegrees(rotationDegrees);
      }

      final inputImage = _toInputImage(img, _mlkitRotation);
      final poses = await _pose.processImage(inputImage);
      debugPrint('[Pose] detected=${poses.length} rot=$_mlkitRotation');

      if (poses.isEmpty) {
        // Auto-rotate probe: cycle through 0/90/180/270 until we get detections
        if (!_rotationLocked) {
          _noDetectFrames++;
          if (_noDetectFrames % 8 == 0) {
            _mlkitRotation = _nextRotation(_mlkitRotation);
            debugPrint('[Pose] rotate probe -> $_mlkitRotation');
          }
        }
        _processing = false;
        return;
      } else {
        // Lock rotation once we see poses
        if (!_rotationLocked) {
          _rotationLocked = true;
          _noDetectFrames = 0;
          debugPrint('[Pose] rotation locked: $_mlkitRotation');
        }
      }

      final pose = poses.first;
      lastPose = pose;

      // Landmarks (RIGHT side)
      final sh = _xyz(pose, PoseLandmarkType.rightShoulder);
      final el = _xyz(pose, PoseLandmarkType.rightElbow);
      final wr = _xyz(pose, PoseLandmarkType.rightWrist);
      final hip = _xyz(pose, PoseLandmarkType.rightHip);
      if (sh == null || el == null || wr == null || hip == null) {
        _processing = false;
        return;
      }

      // 1) Raw features
      final dx = (el.x - sh.x).abs();
      final incl = _degrees(atan2(sh.z - hip.z, sh.y - hip.y));
      final ang = _angleBetween(sh, el, wr);

      // 2) Velocity & wrist height
      final now = DateTime.now().millisecondsSinceEpoch;
      final vel =
          (_prevAng == null || _prevTms == null)
              ? 0.0
              : (ang - _prevAng!) / ((now - _prevTms!) / 1000.0 + 1e-6);
      _prevAng = ang;
      _prevTms = now;
      final wh = wr.y - el.y;

      // 3) Smooth into buffers
      _push(_dx, dx);
      _push(_incl, incl);
      _push(_ang, ang);
      _push(_vel, vel);
      _push(_wh, wh);

      // mc = 1 - (std/ptp) and rom = ptp over last angles
      final arr = _ang.toList();
      final ptp = arr.isEmpty ? 0.0 : (arr.max - arr.min);
      final std = _std(arr);
      final mc = 1.0 - (ptp <= 1e-6 ? 0.0 : (std / (ptp + 1e-6)));
      final rom = ptp;
      _push(_mc, mc);
      _push(_rom, rom);

      // 4) Smoothed
      final dxs = _mean(_dx),
          incs = _mean(_incl),
          angs = _mean(_ang),
          vels = _mean(_vel),
          whs = _mean(_wh),
          mcs = _mean(_mc),
          roms = _mean(_rom);

      // 5) Prompts
      const upTh = 140.0, downTh = 100.0;
      instruction =
          (angs > upTh)
              ? "Raise weight fully"
              : (angs < downTh)
              ? "Lower weight fully"
              : "";

      // 6) ONNX KNN classification
      if (_knn != null) {
        final feats = Float32List.fromList([
          angs,
          dxs,
          incs,
          vels,
          whs,
          mcs,
          roms,
        ]);
        final input = ort.OrtValueTensor.createTensorWithDataList(feats, [
          1,
          7,
        ]);
        final inputName = _knn!.inputNames.first;
        final outputs = _knn!.run(ort.OrtRunOptions(), {
          inputName: input,
        }, _knn!.outputNames);
        final first = outputs.first as ort.OrtValueTensor;
        final scores =
            (first.value as List).map((e) => (e as num).toDouble()).toList();
        final idx = scores.length == 1 ? scores.first.round() : _argmax(scores);
        formLabel =
            (idx >= 0 && idx < _labels.length) ? _labels[idx] : "neutral";
      }

      // 7) FSM + rep counting
      const leanTh = -162.0, swingTh = 0.09;
      if (state == "extended" && angs < downTh) {
        cycleOk = true;
        state = "flexed";
      } else if (state == "flexed") {
        if (incs < leanTh || dxs > swingTh || formLabel != "good") {
          cycleOk = false;
        }
        if (angs > upTh) {
          if (cycleOk) reps += 1;
          state = "extended";
          cycleOk = false;
        }
      }

      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Frame error: $e');
    } finally {
      _processing = false;
    }
  }

  // Helpers
  void _push(ListQueue<double> q, double v) {
    if (q.length >= _windowSize) q.removeFirst();
    q.add(v);
  }

  double _mean(Iterable<double> a) => a.isEmpty ? 0.0 : a.sum / a.length;
  double _degrees(double r) => r * 180.0 / pi;
  double _std(List<double> a) {
    if (a.length < 2) return 0;
    final m = _mean(a);
    return sqrt(a.map((v) => pow(v - m, 2).toDouble()).sum / (a.length - 1));
  }

  int _argmax(List<double> a) {
    var i = 0, bi = 0;
    var best = -1e9;
    for (final v in a) {
      if (v > best) {
        best = v;
        bi = i;
      }
      i++;
    }
    return bi;
  }

  // angle at b formed by a-b-c
  double _angleBetween(_P a, _P b, _P c) {
    final bax = a.x - b.x, bay = a.y - b.y, baz = a.z - b.z;
    final bcx = c.x - b.x, bcy = c.y - b.y, bcz = c.z - b.z;
    final dot = bax * bcx + bay * bcy + baz * bcz;
    final n1 = sqrt(bax * bax + bay * bay + baz * baz) + 1e-6;
    final n2 = sqrt(bcx * bcx + bcy * bcy + bcz * bcz) + 1e-6;
    final cosv = (dot / (n1 * n2)).clamp(-1.0, 1.0);
    return _degrees(acos(cosv));
  }

  _P? _xyz(Pose pose, PoseLandmarkType t) {
    final lmk = pose.landmarks[t];
    if (lmk == null) return null;
    return _P(lmk.x, lmk.y, lmk.z);
  }

  // Convert CameraImage to InputImage (handle platform format)
  InputImage _toInputImage(CameraImage img, InputImageRotation rotation) {
    if (Platform.isAndroid) {
      final nv21 = _yuv420ToNv21(img);
      return InputImage.fromBytes(
        bytes: nv21,
        metadata: InputImageMetadata(
          size: Size(img.width.toDouble(), img.height.toDouble()),
          rotation: rotation,
          format: InputImageFormat.nv21,
          bytesPerRow: img.planes[0].bytesPerRow,
        ),
      );
    } else {
      // iOS BGRA
      final plane = img.planes.first;
      return InputImage.fromBytes(
        bytes: plane.bytes,
        metadata: InputImageMetadata(
          size: Size(img.width.toDouble(), img.height.toDouble()),
          rotation: rotation,
          format: InputImageFormat.bgra8888,
          bytesPerRow: plane.bytesPerRow,
        ),
      );
    }
  }

  InputImageRotation _nextRotation(InputImageRotation r) {
    switch (r) {
      case InputImageRotation.rotation0deg:
        return InputImageRotation.rotation90deg;
      case InputImageRotation.rotation90deg:
        return InputImageRotation.rotation180deg;
      case InputImageRotation.rotation180deg:
        return InputImageRotation.rotation270deg;
      case InputImageRotation.rotation270deg:
        return InputImageRotation.rotation0deg;
    }
  }

  // Map camera rotation degrees to ML Kit rotation
  InputImageRotation _rotationFromDegrees(int degrees) {
    final d = ((degrees % 360) + 360) % 360;
    switch (d) {
      case 0:
        return InputImageRotation.rotation0deg;
      case 90:
        return InputImageRotation.rotation90deg;
      case 180:
        return InputImageRotation.rotation180deg;
      case 270:
        return InputImageRotation.rotation270deg;
      default:
        if (d < 45 || d >= 315) return InputImageRotation.rotation0deg;
        if (d < 135) return InputImageRotation.rotation90deg;
        if (d < 225) return InputImageRotation.rotation180deg;
        return InputImageRotation.rotation270deg;
    }
  }

  // Build NV21 buffer from YUV420 (Android)
  Uint8List _yuv420ToNv21(CameraImage image) {
    final w = image.width;
    final h = image.height;

    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];

    final uvRowStrideU = uPlane.bytesPerRow;
    final uvRowStrideV = vPlane.bytesPerRow;
    final uvPixelStrideU = uPlane.bytesPerPixel ?? 1;
    final uvPixelStrideV = vPlane.bytesPerPixel ?? 1;

    // NV21: Y plane + interleaved VU
    final out = Uint8List(w * h + (w * h >> 1));

    // Copy Y
    out.setRange(0, w * h, yPlane.bytes);

    // Interleave V (Cr) and U (Cb) as VU
    var o = w * h;
    for (int row = 0; row < h ~/ 2; row++) {
      final uRow = row * uvRowStrideU;
      final vRow = row * uvRowStrideV;
      for (int col = 0; col < w ~/ 2; col++) {
        final vVal = vPlane.bytes[vRow + col * uvPixelStrideV];
        final uVal = uPlane.bytes[uRow + col * uvPixelStrideU];
        out[o++] = vVal;
        out[o++] = uVal;
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar:
          showCamera
              ? AppBar(
                title: const Text('Bicep Curl'),
                backgroundColor: Colors.black.withValues(alpha: 0.7), // fixed
                foregroundColor: Colors.white,
                elevation: 0,
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => Navigator.pop(context),
                ),
                actions: [
                  // Reset auto-rotation to re-probe if needed
                  IconButton(
                    icon: const Icon(Icons.screen_rotation_alt),
                    tooltip: 'Re-calibrate rotation',
                    onPressed:
                        () => setState(() {
                          _rotationLocked = false;
                          _noDetectFrames = 0;
                        }),
                  ),
                  IconButton(
                    icon: const Icon(Icons.info_outline),
                    onPressed: _showInstructionsDialog,
                  ),
                  IconButton(
                    icon: Icon(
                      mirrorOverlay ? Icons.flip_camera_android : Icons.flip,
                    ),
                    tooltip: 'Flip overlay',
                    onPressed:
                        () => setState(() => mirrorOverlay = !mirrorOverlay),
                  ),
                  IconButton(
                    icon: const Icon(Icons.videocam_off),
                    onPressed: () => setState(() => showCamera = false),
                    tooltip: 'Turn Off Camera',
                  ),
                ],
              )
              : AppBar(
                title: const Text('Bicep Curl'),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.info_outline),
                    onPressed: _showInstructionsDialog,
                  ),
                ],
              ),
      body:
          showCamera
              ? Stack(
                children: [
                  // Use shared CameraWidget for camera lifecycle + frames
                  Positioned.fill(
                    child: CameraWidget(
                      showCamera: showCamera,
                      onToggleCamera: () => setState(() => showCamera = false),
                      onImage:
                          (image, rotation, mirror) => _onImage(
                            image,
                            rotation,
                            mirror: mirrorOverlay,
                            rotation: _mlkitRotation,
                          ),
                    ),
                  ),
                  // Overlay
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _PosePainter(
                          lastPose,
                          imageSize: _imageSize,
                          mirror: mirrorOverlay,
                        ),
                      ),
                    ),
                  ),
                  // HUD
                  Positioned(
                    top: 16,
                    left: 16,
                    child: _hud("INSTRUCTION", instruction),
                  ),
                  Positioned(top: 56, left: 16, child: _hud("FORM", formLabel)),
                  Positioned(top: 96, left: 16, child: _hud("REPS", "$reps")),
                ],
              )
              : Container(
                padding: const EdgeInsets.all(24),
                alignment: Alignment.topLeft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Bicep Curl Exercise',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '1) Stand feet shoulder-width apart\n'
                      '2) Keep elbows close to body\n'
                      '3) Curl up, then lower under control',
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: () => setState(() => showCamera = true),
                      icon: const Icon(Icons.videocam),
                      label: const Text('Start Camera'),
                    ),
                  ],
                ),
              ),
    );
  }

  Widget _hud(String k, String v) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: Colors.black54,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      "$k: $v",
      style: const TextStyle(
        color: Colors.white,
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

class _P {
  final double x, y, z;
  _P(this.x, this.y, this.z);
}

class _PosePainter extends CustomPainter {
  final Pose? pose;
  final Size? imageSize;
  final bool mirror;
  _PosePainter(this.pose, {this.imageSize, this.mirror = false});

  @override
  void paint(Canvas c, Size s) {
    if (pose == null) return;

    // scale factors from image-space to canvas-space
    final iw = imageSize?.width ?? s.width;
    final ih = imageSize?.height ?? s.height;
    final sx = s.width / iw;
    final sy = s.height / ih;

    final paint =
        Paint()
          ..strokeWidth = 3
          ..style = PaintingStyle.stroke
          ..color = const Color(0xFF00FF7F);

    Offset mapPoint(PoseLandmark l) {
      final x = l.x * sx;
      final y = l.y * sy;
      final mx = mirror ? (s.width - x) : x;
      return Offset(mx, y);
    }

    final rs = pose!.landmarks[PoseLandmarkType.rightShoulder];
    final re = pose!.landmarks[PoseLandmarkType.rightElbow];
    final rw = pose!.landmarks[PoseLandmarkType.rightWrist];

    if (rs != null && re != null) c.drawLine(mapPoint(rs), mapPoint(re), paint);
    if (re != null && rw != null) c.drawLine(mapPoint(re), mapPoint(rw), paint);

    for (final l in pose!.landmarks.values) {
      c.drawCircle(mapPoint(l), 3, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _PosePainter old) =>
      old.pose != pose || old.imageSize != imageSize || old.mirror != mirror;
}
