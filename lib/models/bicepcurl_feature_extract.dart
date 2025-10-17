import 'dart:math' as math;
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

class BicepCurlFeatureExtractor {
  /// Extract 7 features from pose landmarks for KNN classification
  /// Returns: [ang, dx, incl, vel, wh, mc, rom]
  static List<double> extractFeatures(
    Map<PoseLandmarkType, PoseLandmark> landmarks,
    double previousAngle,
    double previousTime,
    double currentTime,
    double imageWidth,  // Added: for normalization
    double imageHeight, // Added: for normalization
  ) {
    // Get required landmarks
    final rightShoulder = landmarks[PoseLandmarkType.rightShoulder];
    final rightElbow = landmarks[PoseLandmarkType.rightElbow];
    final rightWrist = landmarks[PoseLandmarkType.rightWrist];
    final rightHip = landmarks[PoseLandmarkType.rightHip];

    if (rightShoulder == null || rightElbow == null || 
        rightWrist == null || rightHip == null) {
      return List.filled(7, 0.0); // Return zeros if landmarks missing
    }

    // ═══════════════════════════════════════════════════════════════
    // FEATURE 1: Elbow angle (ang)
    // ═══════════════════════════════════════════════════════════════
    final elbowAngle = _angleBetween(
      rightShoulder,
      rightElbow,
      rightWrist,
    );

    // ═══════════════════════════════════════════════════════════════
    // FEATURE 2: Elbow drift (dx) - horizontal distance from shoulder
    // Python: dx = abs(el[0] - sh[0]) in NORMALIZED coordinates (0.0-1.0)
    // ML Kit returns pixel coordinates, so we MUST normalize by image width
    // ═══════════════════════════════════════════════════════════════
    final leftShoulder = landmarks[PoseLandmarkType.leftShoulder];
    final leftElbow = landmarks[PoseLandmarkType.leftElbow];
    
    // Calculate in pixels first
    final dxPixels = (leftShoulder != null && leftElbow != null)
        ? (leftElbow.x - leftShoulder.x).abs()
        : (rightElbow.x - rightShoulder.x).abs();
    
    // NORMALIZE by image width to get 0.0-1.0 range (matching Python)
    final dx = dxPixels / imageWidth;

    // ═══════════════════════════════════════════════════════════════
    // FEATURE 3: Torso inclination (incl)
    // ═══════════════════════════════════════════════════════════════
    final torsoIncl = _calculateTorsoInclination(rightShoulder, rightHip);

    // ═══════════════════════════════════════════════════════════════
    // FEATURE 4: Angular velocity (vel)
    // ═══════════════════════════════════════════════════════════════
    final timeDelta = currentTime - previousTime;
    final angularVelocity = timeDelta > 0 
        ? (elbowAngle - previousAngle) / timeDelta 
        : 0.0;

    // ═══════════════════════════════════════════════════════════════
    // FEATURE 5: Wrist height relative to elbow (wh)
    // ═══════════════════════════════════════════════════════════════
    final wristHeight = rightWrist.y - rightElbow.y;

    // ═══════════════════════════════════════════════════════════════
    // FEATURE 6 & 7: Movement consistency (mc) and Range of Motion (rom)
    // These will be calculated from smoothing buffers in the main code
    // ═══════════════════════════════════════════════════════════════
    final movementConsistency = 0.5; // Placeholder
    final rangeOfMotion = elbowAngle; // Placeholder

    return [
      elbowAngle,           // 0: ang
      dx,                   // 1: dx
      torsoIncl,            // 2: incl
      angularVelocity,      // 3: vel
      wristHeight,          // 4: wh
      movementConsistency,  // 5: mc
      rangeOfMotion,        // 6: rom
    ];
  }

  /// Calculate angle between three 3D points (a-b-c)
  static double _angleBetween(
    PoseLandmark a,
    PoseLandmark b,
    PoseLandmark c,
  ) {
    // Vector BA (from b to a)
    final bax = a.x - b.x;
    final bay = a.y - b.y;
    final baz = a.z - b.z;

    // Vector BC (from b to c)
    final bcx = c.x - b.x;
    final bcy = c.y - b.y;
    final bcz = c.z - b.z;

    // Dot product: BA · BC
    final dot = bax * bcx + bay * bcy + baz * bcz;

    // Magnitudes: ||BA|| and ||BC||
    final magBA = math.sqrt(bax * bax + bay * bay + baz * baz);
    final magBC = math.sqrt(bcx * bcx + bcy * bcy + bcz * bcz);

    // Cosine of angle: cos(θ) = (BA · BC) / (||BA|| × ||BC||)
    final cosAngle = dot / (magBA * magBC + 1e-6);
    
    // Clamp to [-1, 1] to handle floating point errors
    final angleRad = math.acos(cosAngle.clamp(-1.0, 1.0));

    // Convert to degrees
    return angleRad * (180.0 / math.pi);
  }

  /// Calculate torso inclination angle
  /// Python: degrees(atan2(sh[2] - hip[2], sh[1] - hip[1]))
  static double _calculateTorsoInclination(
    PoseLandmark shoulder,
    PoseLandmark hip,
  ) {
    final dz = shoulder.z - hip.z;
    final dy = shoulder.y - hip.y;
    
    final angleRad = math.atan2(dz, dy);
    return angleRad * (180.0 / math.pi);
  }
}