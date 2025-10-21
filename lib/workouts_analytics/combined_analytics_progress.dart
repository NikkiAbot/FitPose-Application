import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

// Imports from Line Chart
import 'line_chart/presentation/app_resources.dart';
import 'line_chart/line_chart_modules/line_chart_widget.dart';

// Progress widgets used by the tracker
import '/workouts_analytics/progress_tracker/widgets/categories.dart';
import '/workouts_analytics/progress_tracker/widgets/date.dart';
import '/workouts_analytics/progress_tracker/widgets/stats_item.dart';
import '/workouts_analytics/progress_tracker/tracker_model/progressmodel.dart';

class CombinedAnalyticsProgress extends StatefulWidget {
  final Map<int, Map<DateTime, WorkoutProgress>> workoutData;

  const CombinedAnalyticsProgress({super.key, required this.workoutData});

  @override
  State<CombinedAnalyticsProgress> createState() =>
      _CombinedAnalyticsProgressState();
}

class _CombinedAnalyticsProgressState extends State<CombinedAnalyticsProgress> {
  // Shared state between charts and tracker
  DateTime selectedDate = DateTime.now();
  // separate month used for the line chart (month-only)
  DateTime selectedMonth = DateTime(
    DateTime.now().year,
    DateTime.now().month,
    1,
  );

  List<int> activeWorkoutIndices = [0, 1, 2, 3, 4, 5];
  bool isShowingMainData = true;

  // UI helper arrays (same as original tracker)
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

  // Determine which single workout index the tracker should show.
  // If multiple filters are active, prefer the first active index.
  int get selectedWorkoutIndex =>
      activeWorkoutIndices.isNotEmpty ? activeWorkoutIndices.first : 0;

  // Helper: returns true if any workout has progress in selectedMonth
  bool _hasDataInSelectedMonth(DateTime month) {
    for (final workoutMap in widget.workoutData.values) {
      for (final date in workoutMap.keys) {
        if (date.year == month.year && date.month == month.month) {
          return true;
        }
      }
    }
    return false;
  }

  void _onDateSelected(DateTime date) {
    setState(() {
      selectedDate = date;
    });
  }

  void _onMonthPrev() {
    setState(() {
      selectedMonth = DateTime(selectedMonth.year, selectedMonth.month - 1, 1);
    });
  }

  void _onMonthNext() {
    // guard: don't advance past the current month
    final DateTime currentMonthFirst = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      1,
    );
    if (!selectedMonth.isBefore(currentMonthFirst)) return;
    setState(() {
      selectedMonth = DateTime(selectedMonth.year, selectedMonth.month + 1, 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final DateTime currentMonthFirst = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      1,
    );
    final bool monthHasData = _hasDataInSelectedMonth(selectedMonth);

    final workoutColor = _workoutColors[selectedWorkoutIndex];
    final workoutDailyData =
        widget.workoutData[selectedWorkoutIndex] ??
        <DateTime, WorkoutProgress>{};
    final todayProgress =
        workoutDailyData[selectedDate] ??
        WorkoutProgress(reps: 0, sets: 0, duration: Duration());
    final totalProgress = _calculateTotalProgress(workoutDailyData);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 10),
        Text(
          'Workout Posture & Progress',
          style: GoogleFonts.poppins(
            color: AppColors.primary,
            fontSize: 22,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),

        // MONTH NAVIGATOR for the line chart (monthly calendar)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left, size: 20),
                onPressed: _onMonthPrev,
              ),
              Text(
                DateFormat('MMMM yyyy').format(selectedMonth),
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  color: Colors.grey[700],
                ),
              ),
              IconButton(
                // disable next if selectedMonth is the currentMonth or beyond
                icon: const Icon(Icons.chevron_right, size: 20),
                onPressed:
                    selectedMonth.isBefore(currentMonthFirst)
                        ? _onMonthNext
                        : null,
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // Combined charts area: line chart (top) — uses selectedMonth (month-based)
        AspectRatio(
          aspectRatio: 1.20,
          child: Stack(
            children: <Widget>[
              // Chart + surrounding UI
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const SizedBox(height: 4),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 30, left: 10),
                      child: LineChartWidget(
                        isShowingMainData: isShowingMainData,
                        activeIndices: activeWorkoutIndices,
                        // pass the selectedMonth so the chart can display month-based data
                        selectedDate: selectedMonth,
                        hideInternalLegend: true,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const SizedBox(height: 10),
                ],
              ),

              // Refresh button
              Positioned(
                top: 6,
                right: 8,
                child: IconButton(
                  icon: Icon(
                    Icons.refresh,
                    color: Color.fromRGBO(128, 128, 128, 0.8),
                  ),
                  onPressed: () {
                    setState(() {
                      isShowingMainData = !isShowingMainData;
                    });
                  },
                ),
              ),

              // Overlay when no data for selectedMonth: transparent white overlay (no blur)
              if (!monthHasData)
                Positioned.fill(
                  child: Container(
                    // white translucent overlay so chart remains visible underneath
                    color: Colors.white.withValues(alpha: 0.65),
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    // transparent/plain content (no boxed card)
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 36,
                          color: AppColors.primary,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'No tracked progress',
                          style: GoogleFonts.poppins(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'There is no tracked progress for ${DateFormat('MMMM yyyy').format(selectedMonth)}.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            color: Colors.black54,
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // Workout category selector (keeps same UI as progress tracker)
        WorkoutCategorySelector(
          workoutNames: _workoutNames,
          workoutColors: _workoutColors,
          selectedWorkoutIndex: selectedWorkoutIndex,
          onWorkoutSelected: (index) {
            setState(() {
              activeWorkoutIndices = [index];
            });
          },
        ),

        const SizedBox(height: 12),

        // MOVED: DatePicker now sits with the progress tracker (daily selector)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          child: DatePicker(
            selectedDate: selectedDate,
            onDateSelected: _onDateSelected,
            initialDate: DateTime.now(),
            disableFutureDates: true,
            onDateSelection: (d) {},
          ),
        ),

        const SizedBox(height: 12),

        // Progress boxes for selected date and total progress
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
