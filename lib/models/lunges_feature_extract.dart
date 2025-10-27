import 'dart:math' as math;
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

class LungesFeatureExtractor {
  // Important landmarks for lunges (matching Python IMPORTANT_LMS)
  static const List<PoseLandmarkType> importantLandmarks = [
    PoseLandmarkType.nose,
    PoseLandmarkType.leftShoulder,
    PoseLandmarkType.rightShoulder,
    PoseLandmarkType.leftHip,
    PoseLandmarkType.rightHip,
    PoseLandmarkType.leftKnee,
    PoseLandmarkType.rightKnee,
    PoseLandmarkType.leftAnkle,
    PoseLandmarkType.rightAnkle,
    PoseLandmarkType.leftHeel,
    PoseLandmarkType.rightHeel,
    PoseLandmarkType.leftFootIndex,
    PoseLandmarkType.rightFootIndex,
  ];

  /// Extract important keypoints (52 features: 13 landmarks × 4 values [x,y,z,visibility])
  /// Matching Python's extract_important_keypoints function
  static List<double> extractImportantKeypoints(
    Map<PoseLandmarkType, PoseLandmark> landmarks,
  ) {
    final List<double> data = [];

    for (final landmarkType in importantLandmarks) {
      final landmark = landmarks[landmarkType];
      if (landmark != null) {
        data.addAll([
          landmark.x,
          landmark.y,
          landmark.z,
          1.0, // visibility (ML Kit doesn't provide this, default to 1.0)
        ]);
      } else {
        // If landmark not detected, add zeros
        data.addAll([0.0, 0.0, 0.0, 0.0]);
      }
    }

    return data;
  }

  /// Calculate angle between 3 points (matching Python's calculate_angle)
  static double calculateAngle(
    List<double> point1,
    List<double> point2,
    List<double> point3,
  ) {
    final rad1 = math.atan2(point1[1] - point2[1], point1[0] - point2[0]);
    final rad2 = math.atan2(point3[1] - point2[1], point3[0] - point2[0]);

    double angleInRad = rad2 - rad1;
    double angleInDeg = (angleInRad * 180.0 / math.pi).abs();

    if (angleInDeg > 180) {
      angleInDeg = 360 - angleInDeg;
    }

    return angleInDeg;
  }

  /// Analyze knee angles (matching Python's analyze_knee_angle)
  static Map<String, dynamic> analyzeKneeAngle(
    Map<PoseLandmarkType, PoseLandmark> landmarks,
    String stage,
    List<double> angleThresholds, // [min, max] e.g., [60, 135]
  ) {
    final results = {
      'error': false,
      'right': {'error': false, 'angle': 0.0},
      'left': {'error': false, 'angle': 0.0},
    };

    // Right knee angle
    final rightHip = landmarks[PoseLandmarkType.rightHip];
    final rightKnee = landmarks[PoseLandmarkType.rightKnee];
    final rightAnkle = landmarks[PoseLandmarkType.rightAnkle];

    if (rightHip != null && rightKnee != null && rightAnkle != null) {
      (results['right'] as Map<String, dynamic>)['angle'] = calculateAngle(
        [rightHip.x, rightHip.y],
        [rightKnee.x, rightKnee.y],
        [rightAnkle.x, rightAnkle.y],
      );
    }

    // Left knee angle
    final leftHip = landmarks[PoseLandmarkType.leftHip];
    final leftKnee = landmarks[PoseLandmarkType.leftKnee];
    final leftAnkle = landmarks[PoseLandmarkType.leftAnkle];

    if (leftHip != null && leftKnee != null && leftAnkle != null) {
      (results['left'] as Map<String, dynamic>)['angle'] = calculateAngle(
        [leftHip.x, leftHip.y],
        [leftKnee.x, leftKnee.y],
        [leftAnkle.x, leftAnkle.y],
      );
    }

    // Only evaluate errors when in "down" stage
    if (stage != 'down') {
      return results;
    }

    // Check if angles are within acceptable range
    final rightAngle =
        (results['right']! as Map<String, dynamic>)['angle'] as double;
    final leftAngle =
        (results['left']! as Map<String, dynamic>)['angle'] as double;

    if (rightAngle < angleThresholds[0] || rightAngle > angleThresholds[1]) {
      (results['right'] as Map<String, dynamic>)['error'] = true;
      results['error'] = true;
    }

    if (leftAngle < angleThresholds[0] || leftAngle > angleThresholds[1]) {
      (results['left'] as Map<String, dynamic>)['error'] = true;
      results['error'] = true;
    }

    return results;
  }
}
