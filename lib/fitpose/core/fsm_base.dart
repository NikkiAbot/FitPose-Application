class RepFSM {
  final double loweredThresh;
  final double raisedThresh;

  String? state; // null -> waiting
  bool anomaly = false;
  int reps = 0;

  RepFSM({required this.loweredThresh, required this.raisedThresh});

  void update({required double metric, required bool goodForm}) {
    if (state == null) {
      if (metric < loweredThresh) {
        state = "lowered";
        anomaly = false;
      }
      return;
    }

    if (!goodForm) anomaly = true;

    if (state == "lowered") {
      if (metric > raisedThresh) state = "raised";
    } else if (state == "raised") {
      if (metric < loweredThresh) {
        if (!anomaly) reps += 1;
        state = "lowered";
        anomaly = false;
      }
    }
  }

  String get stateText => state ?? "waiting";
}
