import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '/analytics/presentation/app_resources.dart';

import 'model/progressmodel.dart';
import 'widgets/categories.dart';
import 'widgets/date.dart';
import 'widgets/stats_item.dart';

class ProgressTracker extends StatefulWidget {
  final Map<int, Map<DateTime, WorkoutProgress>> workoutData;

  const ProgressTracker({super.key, required this.workoutData});

  @override
  State<ProgressTracker> createState() => _ProgressTrackerState();
}

class _ProgressTrackerState extends State<ProgressTracker> {
  final List<String> _workoutNames = [
    'Squat',
    'Plank',
    'Push Up',
    'Shoulder Press',
    'Bicep Curl',
    'Lunges',
  ];

  final List<Color> _workoutColors = [
    AppColors.contentColorGreen,
    AppColors.contentColorPink,
    AppColors.contentColorCyan,
    Colors.orange,
    Colors.purple,
    Colors.amber,
  ];

  int selectedWorkoutIndex = 0;
  DateTime selectedDate = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final workoutColor = _workoutColors[selectedWorkoutIndex];
    final workoutDailyData = widget.workoutData[selectedWorkoutIndex] ?? {};
    final todayProgress =
        workoutDailyData[selectedDate] ??
        WorkoutProgress(reps: 0, sets: 0, duration: Duration());
    final totalProgress = _calculateTotalProgress(workoutDailyData);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        WorkoutCategorySelector(
          workoutNames: _workoutNames,
          workoutColors: _workoutColors,
          selectedWorkoutIndex: selectedWorkoutIndex,
          onWorkoutSelected:
              (index) => setState(() => selectedWorkoutIndex = index),
        ),
        DatePicker(
          selectedDate: selectedDate,
          onDateSelected: (date) => setState(() => selectedDate = date),
          initialDate: DateTime.now(),
          disableFutureDates: true,
          onDateSelection: (selectedDate) {},
        ),
        const SizedBox(height: 16),
        ProgressBox(
          title: "Progress on ${DateFormat('yMMMd').format(selectedDate)}",
          progress: todayProgress,
          color: workoutColor,
        ),
        const SizedBox(height: 12),
        ProgressBox(
          title: "Total Progress",
          progress: totalProgress,
          color: workoutColor,
        ),
      ],
    );
  }

  WorkoutProgress _calculateTotalProgress(Map<DateTime, WorkoutProgress> data) {
    int totalReps = 0;
    int totalSets = 0;
    Duration totalDuration = Duration();

    for (var progress in data.values) {
      totalReps += progress.reps;
      totalSets += progress.sets;
      totalDuration += progress.duration;
    }
    return WorkoutProgress(
      reps: totalReps,
      sets: totalSets,
      duration: totalDuration,
    );
  }
}
