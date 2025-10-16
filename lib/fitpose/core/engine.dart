import 'package:camera/camera.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import 'pose_service.dart';
import 'utils_image.dart';

abstract class ExerciseFeatures {
  double get primaryMetric;        // the FSM-driving value (e.g., avg elbow angle)
  List<double> toList();
}

abstract class FeatureExtractor<F extends ExerciseFeatures> {
  F compute(Pose pose);
}

abstract class ExerciseClassifier {
  ({String label, bool good}) classify(List<double> features);
}

class ExerciseEngine<F extends ExerciseFeatures> {
  final PoseService _pose = PoseService();
  final FeatureExtractor<F> extractor;
  final ExerciseClassifier classifier;

  ExerciseEngine({required this.extractor, required this.classifier});

  Future<({F? feats, String label, bool good})> process(CameraImage img, int rotation) async {
    final input = inputImageFromCameraImage(img, rotation);
    final pose = await _pose.processImage(input);
    if (pose == null) return (feats: null, label: "No Pose", good: false);
    final feats = extractor.compute(pose);
    final res = classifier.classify(feats.toList());
    return (feats: feats, label: res.label, good: res.good);
  }

  Future<void> close() => _pose.close();
}
