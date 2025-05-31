class WorkoutUtils {
  static String getDateForXValue(double x) {
    if (x <= 3) return 'Early May';
    if (x <= 7) return 'Mid May';
    if (x <= 11) return 'Late May';
    return 'End of May';
  }

  static String workoutName(int index) {
    switch (index) {
      case 0:
        return 'Squat';
      case 1:
        return 'Plank';
      case 2:
        return 'Push Up';
      case 3:
        return 'Shoulder Press';
      case 4:
        return 'Bicep Curl';
      case 5:
        return 'Lunges';
      default:
        return '';
    }
  }
}
