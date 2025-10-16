import 'dart:math' as math;
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

/// Extracts the 7 features for shoulder press form analysis
/// Matches the Python feature engineering exactly
class ShoulderPressFeatures {
  // Landmark indices from MediaPipe Pose (matching your feature_info.json)
  static const int LS = 11; // left_shoulder
  static const int RS = 12; // right_shoulder
  static const int LE = 13; // left_elbow
  static const int RE = 14; // right_elbow
  static const int LW = 15; // left_wrist
  static const int RW = 16; // right_wrist
  static const int LH = 23; // left_hip
  static const int RH = 24; // right_hip

  /// Compute the 7 features exactly as in your Python code:
  /// 1. left_elbow_angle
  /// 2. right_elbow_angle
  /// 3. shoulder_width
  /// 4. wrist_shoulder_diff_left
  /// 5. wrist_shoulder_diff_right
  /// 6. trunk_angle
  /// 7. elbow_angle_diff
  static List<double>? computeFeatures(Pose pose) {
    final landmarks = pose.landmarks;
    
    // Get required landmarks
    final ls = landmarks[PoseLandmarkType.leftShoulder];
    final rs = landmarks[PoseLandmarkType.rightShoulder];
    final le = landmarks[PoseLandmarkType.leftElbow];
    final re = landmarks[PoseLandmarkType.rightElbow];
    final lw = landmarks[PoseLandmarkType.leftWrist];
    final rw = landmarks[PoseLandmarkType.rightWrist];
    final lh = landmarks[PoseLandmarkType.leftHip];
    final rh = landmarks[PoseLandmarkType.rightHip];

    // Check if all required landmarks are present
    if ([ls, rs, le, re, lw, rw, lh, rh].any((lm) => lm == null)) {
      return null; // Missing landmarks
    }

    // Create coordinate map (matching Python's coords dict)
    final coords = {
      LS: _Point(ls!.x, ls.y),
      RS: _Point(rs!.x, rs.y),
      LE: _Point(le!.x, le.y),
      RE: _Point(re!.x, re.y),
      LW: _Point(lw!.x, lw.y),
      RW: _Point(rw!.x, rw.y),
      LH: _Point(lh!.x, lh.y),
      RH: _Point(rh!.x, rh.y),
    };

    // 1) left_elbow_angle: angle at left elbow (shoulder-elbow-wrist)
    final leftElbowAngle = _angleAt(coords[LS]!, coords[LE]!, coords[LW]!);

    // 2) right_elbow_angle: angle at right elbow (shoulder-elbow-wrist)
    final rightElbowAngle = _angleAt(coords[RS]!, coords[RE]!, coords[RW]!);

    // 3) shoulder_width: distance between shoulders (clipped to avoid division by zero)
    final shoulderWidth = _distance(coords[LS]!, coords[RS]!).clamp(1e-6, double.infinity);

    // 4) wrist_shoulder_diff_left: (left_shoulder.y - left_wrist.y) / shoulder_width
    // Normalized vertical distance between left wrist and shoulder
    final wristShoulderDiffLeft = (coords[LS]!.y - coords[LW]!.y) / shoulderWidth;

    // 5) wrist_shoulder_diff_right: (right_shoulder.y - right_wrist.y) / shoulder_width
    final wristShoulderDiffRight = (coords[RS]!.y - coords[RW]!.y) / shoulderWidth;

    // 6) trunk_angle: angle between trunk and vertical reference
    // Calculate mid-points
    final midSh = _Point(
      (coords[LS]!.x + coords[RS]!.x) / 2,
      (coords[LS]!.y + coords[RS]!.y) / 2,
    );
    final midHp = _Point(
      (coords[LH]!.x + coords[RH]!.x) / 2,
      (coords[LH]!.y + coords[RH]!.y) / 2,
    );
    // Reference point for vertical (1.0 unit to the right of mid-shoulder)
    final refPt = _Point(midSh.x + 1.0, midSh.y);
    final trunkAngle = _angleAt(midHp, midSh, refPt);

    // 7) elbow_angle_diff: absolute difference between left and right elbow angles
    final elbowAngleDiff = (leftElbowAngle - rightElbowAngle).abs();

    // Return features in exact order matching feature_info.json
    return [
      leftElbowAngle,           // Feature 0
      rightElbowAngle,          // Feature 1
      shoulderWidth,            // Feature 2
      wristShoulderDiffLeft,    // Feature 3
      wristShoulderDiffRight,   // Feature 4
      trunkAngle,               // Feature 5
      elbowAngleDiff,           // Feature 6
    ];
  }

  /// Calculate angle at point b formed by vectors ba and bc
  /// Uses dot product formula: cos(θ) = (ba · bc) / (|ba| * |bc|)
  /// Matches your Python: angle_at(a, b, c)
  static double _angleAt(_Point a, _Point b, _Point c) {
    // Vectors from b to a and b to c
    final ba = _Point(a.x - b.x, a.y - b.y);
    final bc = _Point(c.x - b.x, c.y - b.y);

    // Dot product: ba · bc
    final dot = ba.x * bc.x + ba.y * bc.y;

    // Magnitudes: |ba| and |bc|
    final magBa = math.sqrt(ba.x * ba.x + ba.y * ba.y);
    final magBc = math.sqrt(bc.x * bc.x + bc.y * bc.y);

    // Denominator with small epsilon to prevent division by zero
    final denom = (magBa * magBc) + 1e-7;

    // Cosine of angle (clamped to [-1, 1] for numerical stability)
    final cosTheta = (dot / denom).clamp(-1.0, 1.0);

    // Convert to degrees: θ = arccos(cosTheta) * (180/π)
    return math.acos(cosTheta) * (180.0 / math.pi);
  }

  /// Calculate Euclidean distance between two points
  /// Matches Python: np.linalg.norm(coords[LS] - coords[RS], axis=1)
  static double _distance(_Point a, _Point b) {
    final dx = a.x - b.x;
    final dy = a.y - b.y;
    return math.sqrt(dx * dx + dy * dy);
  }
}

/// Simple point class for coordinate calculations
class _Point {
  final double x;
  final double y;

  _Point(this.x, this.y);
}