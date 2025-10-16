import '../../core/engine.dart';

class ShoulderPressClassifier implements ExerciseClassifier {
  @override
  ({String label, bool good}) classify(List<double> f) {
    // f: [left, right, shoulderWidth, wristL, wristR, trunk, diff]
    final left = f[0], right = f[1], trunk = f[5], diff = f[6];
    final extended = (left > 155 && right > 155);
    final upright  = (trunk < 15);
    final balanced = (diff < 12);

    if (extended && upright && balanced) return (label: "Good-Form", good: true);
    if (!upright) return (label: "Back-Arch", good: false);
    if (!extended) return (label: "Half-Rep", good: false);
    return (label: "Form-Alert", good: false);
  }
}
