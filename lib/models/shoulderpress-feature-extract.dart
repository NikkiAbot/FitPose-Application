import 'dart:math';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:flutter/foundation.dart';
import 'dart:ui';

class ShoulderPressFeatures {
  // *** FIX: Use L1 norm like Python ***
  static double _angle(Offset a, Offset b, Offset c) {
    final ab = a - b;
    final cb = c - b;
    
    final dot = ab.dx * cb.dx + ab.dy * cb.dy;
    
    // *** L1 NORM (Manhattan distance) - matches Python ***
    final normAB = ab.dx.abs() + ab.dy.abs();
    final normCB = cb.dx.abs() + cb.dy.abs();
    final denom = (normAB * normCB) + 1e-7;
    
    final cosv = (dot / denom).clamp(-1.0, 1.0);
    return (180 / pi) * acos(cosv);
  }

  static double _euclideanDistance(Offset a, Offset b) {
    final dx = a.dx - b.dx;
    final dy = a.dy - b.dy;
    return sqrt(dx * dx + dy * dy);
  }

  static List<double>? computeFeatures(Pose pose) {
    final lm = pose.landmarks;

    // Get landmarks (matching Python indices)
    final leftShoulder = lm[PoseLandmarkType.leftShoulder];    // 11
    final rightShoulder = lm[PoseLandmarkType.rightShoulder];  // 12
    final leftElbow = lm[PoseLandmarkType.leftElbow];          // 13
    final rightElbow = lm[PoseLandmarkType.rightElbow];        // 14
    final leftWrist = lm[PoseLandmarkType.leftWrist];          // 15
    final rightWrist = lm[PoseLandmarkType.rightWrist];        // 16
    final leftHip = lm[PoseLandmarkType.leftHip];              // 23
    final rightHip = lm[PoseLandmarkType.rightHip];            // 24

    if ([leftShoulder, rightShoulder, leftElbow, rightElbow, 
         leftWrist, rightWrist, leftHip, rightHip].any((p) => p == null)) {
      if (kDebugMode) print('[Features] Missing landmarks');
      return null;
    }

    // 1. Left elbow angle (L1 norm like Python)
    final leftElbowAngle = _angle(
      Offset(leftShoulder!.x, leftShoulder.y),
      Offset(leftElbow!.x, leftElbow.y),
      Offset(leftWrist!.x, leftWrist.y),
    );

    // 2. Right elbow angle (L1 norm like Python)
    final rightElbowAngle = _angle(
      Offset(rightShoulder!.x, rightShoulder.y),
      Offset(rightElbow!.x, rightElbow.y),
      Offset(rightWrist!.x, rightWrist.y),
    );

    // 3. Shoulder width (Euclidean distance, then clamp)
    final shoulderWidth = _euclideanDistance(
      Offset(leftShoulder.x, leftShoulder.y),
      Offset(rightShoulder.x, rightShoulder.y),
    ).clamp(1e-6, double.infinity);

    // 4. Wrist-shoulder vertical difference divided by shoulder width
    final wristShoulderDiffLeft = 
        (leftShoulder.y - leftWrist.y) / shoulderWidth;

    // 5. Wrist-shoulder vertical difference (right)
    final wristShoulderDiffRight = 
        (rightShoulder.y - rightWrist.y) / shoulderWidth;

    // 6. Trunk angle calculation
    final midShoulder = Offset(
      (leftShoulder.x + rightShoulder.x) / 2,
      (leftShoulder.y + rightShoulder.y) / 2,
    );
    final midHip = Offset(
      (leftHip!.x + rightHip!.x) / 2,
      (leftHip.y + rightHip.y) / 2,
    );
    
    // Reference point: horizontal line from mid_shoulder
    final refPoint = Offset(midShoulder.dx + 1.0, midShoulder.dy);
    final trunkAngle = _angle(midHip, midShoulder, refPoint);

    // 7. Elbow angle difference (absolute)
    final elbowAngleDiff = (leftElbowAngle - rightElbowAngle).abs();

    final features = [
      leftElbowAngle,
      rightElbowAngle,
      shoulderWidth,
      wristShoulderDiffLeft,
      wristShoulderDiffRight,
      trunkAngle,
      elbowAngleDiff,
    ];

    if (kDebugMode) {
      print('╔════════════════════════════════════════════════════════╗');
      print('║  FEATURE EXTRACTION (L1 Norm - Python Match)           ║');
      print('╠════════════════════════════════════════════════════════╣');
      print('║  1. left_elbow_angle:          ${leftElbowAngle.toStringAsFixed(2).padLeft(7)}°  ║');
      print('║  2. right_elbow_angle:         ${rightElbowAngle.toStringAsFixed(2).padLeft(7)}°  ║');
      print('║  3. shoulder_width:            ${shoulderWidth.toStringAsFixed(4).padLeft(7)}   ║');
      print('║  4. wrist_shoulder_diff_left:  ${wristShoulderDiffLeft.toStringAsFixed(4).padLeft(7)}   ║');
      print('║  5. wrist_shoulder_diff_right: ${wristShoulderDiffRight.toStringAsFixed(4).padLeft(7)}   ║');
      print('║  6. trunk_angle:               ${trunkAngle.toStringAsFixed(2).padLeft(7)}°  ║');
      print('║  7. elbow_angle_diff:          ${elbowAngleDiff.toStringAsFixed(2).padLeft(7)}°  ║');
      print('╚════════════════════════════════════════════════════════╝');
    }

    return features;
  }
}