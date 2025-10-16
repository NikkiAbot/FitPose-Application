import 'dart:math' as math;
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import '../../core/engine.dart';

const LS = PoseLandmarkType.leftShoulder;
const RS = PoseLandmarkType.rightShoulder;
const LE = PoseLandmarkType.leftElbow;
const RE = PoseLandmarkType.rightElbow;
const LW = PoseLandmarkType.leftWrist;
const RW = PoseLandmarkType.rightWrist;
const LH = PoseLandmarkType.leftHip;
const RH = PoseLandmarkType.rightHip;

class ShoulderPressFeats extends ExerciseFeatures {
  final double leftElbowAngle, rightElbowAngle, shoulderWidth;
  final double wristShoulderDiffLeft, wristShoulderDiffRight;
  final double trunkAngle, elbowAngleDiff;

  ShoulderPressFeats({
    required this.leftElbowAngle,
    required this.rightElbowAngle,
    required this.shoulderWidth,
    required this.wristShoulderDiffLeft,
    required this.wristShoulderDiffRight,
    required this.trunkAngle,
    required this.elbowAngleDiff,
  });

  @override
  double get primaryMetric => 0.5 * (leftElbowAngle + rightElbowAngle);

  @override
  List<double> toList() => [
        leftElbowAngle, rightElbowAngle, shoulderWidth,
        wristShoulderDiffLeft, wristShoulderDiffRight,
        trunkAngle, elbowAngleDiff,
      ];
}

double _angleAt(List<double> a, List<double> b, List<double> c) {
  final bax = a[0]-b[0], bay = a[1]-b[1];
  final bcx = c[0]-b[0], bcy = c[1]-b[1];
  final dot = bax*bcx + bay*bcy;
  final nba = math.sqrt(bax*bax + bay*bay);
  final nbc = math.sqrt(bcx*bcx + bcy*bcy);
  final denom = (nba*nbc) + 1e-7;
  var cosv = dot/denom;
  if (cosv > 1) cosv = 1;
  if (cosv < -1) cosv = -1;
  return (math.acos(cosv) * 180.0 / math.pi);
}

class ShoulderPressExtractor implements FeatureExtractor<ShoulderPressFeats> {
  @override
  ShoulderPressFeats compute(Pose pose) {
    List<double> xy(PoseLandmarkType t) {
      final p = pose.landmarks[t]!;
      return [p.x, p.y];
    }

    final ls = xy(LS), rs = xy(RS), le = xy(LE), re = xy(RE);
    final lw = xy(LW), rw = xy(RW), lh = xy(LH), rh = xy(RH);

    final leftElbowAngle  = _angleAt(ls, le, lw);
    final rightElbowAngle = _angleAt(rs, re, rw);

    final shoulderWidth = math.max(
      1e-6,
      math.sqrt(math.pow(ls[0]-rs[0],2) + math.pow(ls[1]-rs[1],2)),
    );

    final wristShoulderDiffLeft  = (ls[1] - lw[1]) / shoulderWidth;
    final wristShoulderDiffRight = (rs[1] - rw[1]) / shoulderWidth;

    final midSh = [(ls[0]+rs[0])/2, (ls[1]+rs[1])/2];
    final midHp = [(lh[0]+rh[0])/2, (lh[1]+rh[1])/2];
    final refPt = [midSh[0] + 1.0, midSh[1]];
    final trunkAngle = _angleAt(midHp, midSh, refPt);

    final elbowAngleDiff = (leftElbowAngle - rightElbowAngle).abs();

    return ShoulderPressFeats(
      leftElbowAngle: leftElbowAngle,
      rightElbowAngle: rightElbowAngle,
      shoulderWidth: shoulderWidth,
      wristShoulderDiffLeft: wristShoulderDiffLeft,
      wristShoulderDiffRight: wristShoulderDiffRight,
      trunkAngle: trunkAngle,
      elbowAngleDiff: elbowAngleDiff,
    );
  }
}
