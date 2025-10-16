import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

class PoseService {
  // Create a PoseDetector with compatible options
  final PoseDetector _detector = PoseDetector(
    options: PoseDetectorOptions(
      mode: PoseDetectionMode.stream, // continuous frame mode
      model: PoseDetectionModel.accurate, // 'base' is faster but less precise
    ),
  );

  bool _busy = false;

  Future<Pose?> processImage(InputImage image) async {
    if (_busy) return null;
    _busy = true;

    try {
      final poses = await _detector.processImage(image);

      // Debug heartbeat
      // ignore: avoid_print
      print('POSES DETECTED: ${poses.length}');

      if (poses.isNotEmpty) {
        return poses.first;
      } else {
        return null;
      }
    } catch (e) {
      print('Pose detection error: $e');
      return null;
    } finally {
      _busy = false;
    }
  }

  Future<void> close() async => _detector.close();
}
