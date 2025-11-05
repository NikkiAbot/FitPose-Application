import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';

class WorkoutAnalyticsWidget extends StatefulWidget {
  final String exercise;

  const WorkoutAnalyticsWidget({super.key, required this.exercise});

  @override
  State<WorkoutAnalyticsWidget> createState() => _WorkoutAnalyticsWidgetState();
}

enum GraphFilter { reps, sets, accuracy, duration }

class _WorkoutAnalyticsWidgetState extends State<WorkoutAnalyticsWidget> {
  DateTime selectedDate = DateTime.now();

  // Totals
  int dailyReps = 0;
  int dailySets = 0;
  int dailyDuration = 0;

  int totalReps = 0;
  int totalSets = 0;
  int totalDuration = 0;

  // NEW: attempted reps (no UI usage; backend analytics only)
  int dailyAttemptedReps = 0;
  int totalAttemptedReps = 0;

  bool isLoading = true;

  // Graph
  List<FlSpot> monthlySpots = [];
  List<double> monthlyRawValues =
      []; // NEW: raw values matching each spot (same order as monthlySpots)
  int maxY = 30;
  GraphFilter selectedFilter = GraphFilter.reps;

  @override
  void initState() {
    super.initState();
    // Fetch analytics immediately when widget is first created
    _fetchAnalytics();
  }

  @override
  void didUpdateWidget(covariant WorkoutAnalyticsWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.exercise != widget.exercise) {
      _fetchAnalytics();
    }
  }

  Future<void> _fetchAnalytics() async {
    setState(() => isLoading = true);

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final collection = FirebaseFirestore.instance.collection(
      '${widget.exercise}_sessions',
    );

    final querySnapshot =
        await collection.where('userId', isEqualTo: uid).get();

    int dr = 0, ds = 0, dd = 0;
    int tr = 0, ts = 0, td = 0;
    // NEW: accumulators for attempted reps
    int dar = 0, tar = 0;
    List<FlSpot> tempSpots = [];
    int tempMax = 0;

    // NEW: per-day aggregators for accuracy chart
    final Map<int, int> repsPerDay = {};
    final Map<int, int> attemptsPerDay = {};
    // NEW: accuracy spots container
    List<FlSpot> tempAccuracySpots = [];

    // NEW: plank-specific per-day aggregates for accuracy
    final Map<int, int> plankDurationPerDay = {};
    final Map<int, int> plankAttemptPerDay = {};
    // NEW: plank accuracy spots
    List<FlSpot> tempPlankAccuracySpots = [];

    final isPlank = widget.exercise.toLowerCase() == 'plank';
    // Remap reps/sets to duration when on plank
    final effectiveFilter =
        isPlank &&
                (selectedFilter == GraphFilter.reps ||
                    selectedFilter == GraphFilter.sets)
            ? GraphFilter.duration
            : selectedFilter;

    // NEW: collect the raw (unbucketed) y-value for each spot
    final List<double> tempRawValues = [];

    for (var doc in querySnapshot.docs) {
      final data = doc.data();
      final tsField = data['timestamp'] as Timestamp?;
      if (tsField == null) continue;

      final date = tsField.toDate();
      final duration = data['duration'] as int? ?? 0;

      // Totals
      td += duration;
      if (_isSameDate(date, selectedDate)) dd += duration;

      if (!isPlank) {
        final reps = data['reps'] as int? ?? 0;
        final sets = data['sets'] as int? ?? 0;
        final attempts = data['attemptedReps'] as int? ?? 0;
        // NEW: pull attempted reps from Firestore

        tr += reps;
        ts += sets;
        // NEW: total attempted reps
        tar += attempts;

        if (_isSameDate(date, selectedDate)) {
          dr += reps;
          ds += sets;
          // NEW: daily attempted reps
          dar += attempts;
        }

        // Graph: sets (sets bucketed, reps bucketed)
        if (date.year == selectedDate.year &&
            date.month == selectedDate.month) {
          double y;
          if (selectedFilter == GraphFilter.reps) {
            // Align reps to Y-axis buckets (0..10)
            y = _getRepsYIndex(reps).toDouble();
            // NEW: store raw reps for tooltip
            tempRawValues.add(reps.toDouble());
          } else if (selectedFilter == GraphFilter.sets) {
            // Align sets to Y-axis buckets (0..6)
            y = _getSetsYIndex(sets).toDouble();
            // NEW: store raw sets for tooltip
            tempRawValues.add(sets.toDouble());
          } else {
            y = sets.toDouble(); // not used; kept for completeness
          }
          tempSpots.add(FlSpot(date.day.toDouble(), y));
          // accuracy per-day aggregates
          final day = date.day;
          repsPerDay[day] = (repsPerDay[day] ?? 0) + reps;
          attemptsPerDay[day] = (attemptsPerDay[day] ?? 0) + attempts;
        }
      } else {
        // Plank: duration + attemptedPlank
        if (date.year == selectedDate.year &&
            date.month == selectedDate.month) {
          // Align duration to Y-axis buckets (0..8)
          int yIndex = _getPlankYIndex(duration);
          tempSpots.add(FlSpot(date.day.toDouble(), yIndex.toDouble()));
          // NEW: store raw duration (seconds) for tooltip
          tempRawValues.add(duration.toDouble());
          if (yIndex > tempMax) tempMax = yIndex;

          // NEW: accumulate per-day for accuracy = duration / attemptedPlank
          final attemptsDur = data['attemptedPlank'] as int? ?? 0;
          final day = date.day;
          plankDurationPerDay[day] = (plankDurationPerDay[day] ?? 0) + duration;
          plankAttemptPerDay[day] =
              (plankAttemptPerDay[day] ?? 0) + attemptsDur;
        }
      }
    }

    // Build accuracy spots for non-plank (reps/attempts)
    if (!isPlank) {
      final days =
          <int>{...repsPerDay.keys, ...attemptsPerDay.keys}.toList()..sort();
      for (final d in days) {
        final r = repsPerDay[d] ?? 0;
        final a = attemptsPerDay[d] ?? 0;
        final acc = formAccuracy(r, a);
        tempAccuracySpots.add(FlSpot(d.toDouble(), acc));
      }
    } else {
      // NEW: Build accuracy spots for plank (duration/attemptedPlank)
      final days =
          <int>{
              ...plankDurationPerDay.keys,
              ...plankAttemptPerDay.keys,
            }.toList()
            ..sort();
      for (final d in days) {
        final dur = plankDurationPerDay[d] ?? 0;
        final att = plankAttemptPerDay[d] ?? 0;
        final acc = formAccuracy(dur, att);
        tempPlankAccuracySpots.add(FlSpot(d.toDouble(), acc));
      }
    }

    setState(() {
      dailyReps = dr;
      dailySets = ds;
      dailyDuration = dd;

      totalReps = tr;
      totalSets = ts;
      totalDuration = td;

      // NEW: publish attempted reps to state (no UI)
      dailyAttemptedReps = dar;
      totalAttemptedReps = tar;

      // Select graph data + raw values in the same order
      if (isPlank) {
        if (effectiveFilter == GraphFilter.accuracy) {
          monthlySpots = tempPlankAccuracySpots;
          // NEW: for accuracy show percentage; raw equals the y of the spot
          monthlyRawValues = tempPlankAccuracySpots.map((s) => s.y).toList();
        } else {
          monthlySpots = tempSpots;
          monthlyRawValues = List<double>.from(tempRawValues);
        }
      } else {
        if (selectedFilter == GraphFilter.accuracy) {
          monthlySpots = tempAccuracySpots;
          // NEW: for accuracy show percentage; raw equals the y of the spot
          monthlyRawValues = tempAccuracySpots.map((s) => s.y).toList();
        } else {
          monthlySpots = tempSpots;
          monthlyRawValues = List<double>.from(tempRawValues);
        }
      }

      // Y-axis range per mode
      maxY =
          isPlank
              ? (effectiveFilter == GraphFilter.accuracy ? 100 : 8)
              : (selectedFilter == GraphFilter.accuracy
                  ? 100
                  : (selectedFilter == GraphFilter.sets ? 6 : 10));

      isLoading = false;
    });
  }

  // Replace helpers with integer bucket indices:

  int _getPlankYIndex(int seconds) {
    if (seconds <= 0) return 0;
    if (seconds <= 10) return 1;
    if (seconds <= 20) return 2;
    if (seconds <= 35) return 3;
    if (seconds <= 50) return 4;
    if (seconds <= 60) return 5;
    if (seconds <= 75) return 6;
    if (seconds <= 85) return 7;
    return 8;
  }

  int _getSetsYIndex(int sets) {
    if (sets <= 5) return 0; // 0-5
    if (sets <= 10) return 1; // 6-10
    if (sets <= 15) return 2; // 11-15
    if (sets <= 20) return 3; // 16-20
    if (sets <= 30) return 4; // 21-30
    if (sets <= 40) return 5; // 31-40
    return 6; // 41-50+
  }

  int _getRepsYIndex(int reps) {
    if (reps <= 0) return 0; // 0
    if (reps <= 4) return 1; // 1-4
    if (reps <= 8) return 2; // 5-8
    if (reps <= 12) return 3; // 9-12
    if (reps <= 16) return 4; // 13-16
    if (reps <= 20) return 5; // 17-20
    if (reps <= 24) return 6; // 21-24
    if (reps <= 28) return 7; // 25-28
    if (reps <= 32) return 8; // 29-32
    if (reps <= 36) return 9; // 33-36
    return 10; // 37-40+
  }

  bool _isSameDate(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _formatDuration(int seconds) {
    final minutes = (seconds ~/ 60).toString().padLeft(2, '0');
    final secs = (seconds % 60).toString().padLeft(2, '0');
    return '$minutes:$secs';
  }

  Future<void> _pickDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(2023),
      lastDate: DateTime.now(),
    );
    if (picked != null && picked != selectedDate) {
      setState(() => selectedDate = picked);
      await _fetchAnalytics();
    }
  }

  void _changeFilter(GraphFilter filter) async {
    if (filter != selectedFilter) {
      setState(() => selectedFilter = filter);
      await _fetchAnalytics();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPlank = widget.exercise.toLowerCase() == 'plank';
    final effectiveFilter =
        isPlank &&
                (selectedFilter == GraphFilter.reps ||
                    selectedFilter == GraphFilter.sets)
            ? GraphFilter.duration
            : selectedFilter;

    return Column(
      children: [
        // Date picker (modern pill)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.blueGrey.shade100, Colors.blueGrey.shade50],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.blueGrey.shade200, width: 1),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 6,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.calendar_today,
                      size: 16,
                      color: Colors.blueGrey,
                    ),
                    const SizedBox(width: 8),
                    RichText(
                      text: TextSpan(
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.black87,
                        ),
                        children: [
                          TextSpan(
                            text: DateFormat.MMMM().format(selectedDate),
                            style: const TextStyle(fontSize: 19),
                          ),
                          TextSpan(
                            text: ' ${DateFormat('d, y').format(selectedDate)}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(
                  Icons.edit_calendar,
                  color: Colors.blueGrey,
                  size: 22,
                ),
                onPressed: () => _pickDate(context),
                tooltip: 'Pick date',
              ),
            ],
          ),
        ),
        const Divider(thickness: 1),

        isLoading
            ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
            : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 6),
                  Text(
                    'Workout Totals',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Colors.grey.shade900,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Totals cards
                  Row(
                    children: [
                      Expanded(
                        child: Card(
                          elevation: 3,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          color: Colors.green.shade50,
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.today,
                                      color: Colors.green.shade700,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Daily Totals',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.green.shade800,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                const Divider(thickness: 1, height: 12),
                                const SizedBox(height: 6),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceAround,
                                  children:
                                      isPlank
                                          ? [
                                            _statItem(
                                              'Duration',
                                              _formatDuration(dailyDuration),
                                              Colors.green.shade800,
                                            ),
                                          ]
                                          : [
                                            _statItem(
                                              'Reps',
                                              dailyReps.toString(),
                                              Colors.green.shade800,
                                            ),
                                            _statItem(
                                              'Sets',
                                              dailySets.toString(),
                                              Colors.green.shade800,
                                            ),
                                            _statItem(
                                              'Duration',
                                              _formatDuration(dailyDuration),
                                              Colors.green.shade800,
                                            ),
                                          ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Card(
                          elevation: 3,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          color: Colors.grey.shade50,
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: const [
                                    Icon(
                                      Icons.all_inclusive,
                                      color: Colors.black54,
                                      size: 18,
                                    ),
                                    SizedBox(width: 6),
                                    Text(
                                      'Overall Totals',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.black87,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                const Divider(thickness: 1, height: 12),
                                const SizedBox(height: 6),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceAround,
                                  children:
                                      isPlank
                                          ? [
                                            _statItem(
                                              'Duration',
                                              _formatDuration(totalDuration),
                                              Colors.black87,
                                            ),
                                          ]
                                          : [
                                            _statItem(
                                              'Reps',
                                              totalReps.toString(),
                                              Colors.black87,
                                            ),
                                            _statItem(
                                              'Sets',
                                              totalSets.toString(),
                                              Colors.black87,
                                            ),
                                            _statItem(
                                              'Duration',
                                              _formatDuration(totalDuration),
                                              Colors.black87,
                                            ),
                                          ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 10),
                  const Divider(thickness: 1),
                  const SizedBox(height: 8),

                  // Graph header + filter
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Monthly Data',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Colors.grey.shade900,
                        ),
                      ),
                      // Non-plank: Reps/Sets/Accuracy
                      if (!isPlank)
                        ToggleButtons(
                          isSelected: [
                            selectedFilter == GraphFilter.reps,
                            selectedFilter == GraphFilter.sets,
                            selectedFilter == GraphFilter.accuracy,
                          ],
                          onPressed: (index) {
                            _changeFilter(
                              index == 0
                                  ? GraphFilter.reps
                                  : index == 1
                                  ? GraphFilter.sets
                                  : GraphFilter.accuracy,
                            );
                          },
                          borderRadius: BorderRadius.circular(10),
                          selectedColor: Colors.white,
                          fillColor: Colors.blue.shade600,
                          color: Colors.blue.shade700,
                          borderColor: Colors.blue.shade200,
                          selectedBorderColor: Colors.blue.shade600,
                          constraints: const BoxConstraints(
                            minHeight: 34,
                            minWidth: 80,
                          ),
                          children: const [
                            Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              child: Text(
                                'Reps',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              child: Text(
                                'Sets',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              child: Text(
                                'Accuracy',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        )
                      else
                        // Plank: Duration/Accuracy
                        ToggleButtons(
                          isSelected: [
                            effectiveFilter == GraphFilter.duration,
                            effectiveFilter == GraphFilter.accuracy,
                          ],
                          onPressed: (index) {
                            _changeFilter(
                              index == 0
                                  ? GraphFilter.duration
                                  : GraphFilter.accuracy,
                            );
                          },
                          borderRadius: BorderRadius.circular(10),
                          selectedColor: Colors.white,
                          fillColor: Colors.blue.shade600,
                          color: Colors.blue.shade700,
                          borderColor: Colors.blue.shade200,
                          selectedBorderColor: Colors.blue.shade600,
                          constraints: const BoxConstraints(
                            minHeight: 34,
                            minWidth: 90,
                          ),
                          children: const [
                            Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              child: Text(
                                'Duration',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              child: Text(
                                'Accuracy',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),

                  const SizedBox(height: 10),

                  // Chart wrapped in a Card
                  Card(
                    elevation: 3,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 12, 12, 10),
                      child: SizedBox(
                        height: 220,
                        child:
                            monthlySpots.isEmpty
                                ? const Center(
                                  child: Text(
                                    'No data for this month',
                                    style: TextStyle(fontSize: 14),
                                  ),
                                )
                                : LineChart(
                                  LineChartData(
                                    minX: 1,
                                    maxX: 31,
                                    minY: 0,
                                    maxY: maxY.toDouble(),

                                    // NEW: align tooltips to axis semantics
                                    lineTouchData: LineTouchData(
                                      enabled: true,
                                      touchTooltipData: LineTouchTooltipData(
                                        fitInsideHorizontally: true,
                                        fitInsideVertically: true,
                                        getTooltipItems: (touchedSpots) {
                                          return touchedSpots.map((barSpot) {
                                            final idx = barSpot.spotIndex.clamp(
                                              0,
                                              monthlyRawValues.length - 1,
                                            );
                                            final raw =
                                                monthlyRawValues.isNotEmpty
                                                    ? monthlyRawValues[idx]
                                                    : barSpot.y;
                                            String txt;

                                            if (isPlank) {
                                              if (effectiveFilter ==
                                                  GraphFilter.accuracy) {
                                                // accuracy: show percentage
                                                txt =
                                                    '${raw.toStringAsFixed(0)}%';
                                              } else {
                                                // duration: show seconds
                                                txt =
                                                    '${raw.toStringAsFixed(0)}s';
                                              }
                                            } else {
                                              if (selectedFilter ==
                                                  GraphFilter.accuracy) {
                                                // accuracy: show percentage
                                                txt =
                                                    '${raw.toStringAsFixed(0)}%';
                                              } else if (selectedFilter ==
                                                  GraphFilter.sets) {
                                                // sets: show raw sets count
                                                txt = raw.toStringAsFixed(0);
                                              } else {
                                                // reps: show raw reps count
                                                txt = raw.toStringAsFixed(0);
                                              }
                                            }

                                            return LineTooltipItem(
                                              txt,
                                              const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            );
                                          }).toList();
                                        },
                                      ),
                                    ),

                                    lineBarsData: [
                                      LineChartBarData(
                                        spots: monthlySpots,
                                        isCurved: false,
                                        barWidth: 0, // hide line
                                        color: Colors.transparent, // hide line
                                        dotData: FlDotData(
                                          show: true,
                                          getDotPainter:
                                              (
                                                spot,
                                                percent,
                                                barData,
                                                index,
                                              ) => FlDotCirclePainter(
                                                radius: 3,
                                                color:
                                                    Colors
                                                        .blue
                                                        .shade600, // visible dot color
                                                strokeWidth: 0,
                                                strokeColor: Colors.transparent,
                                              ),
                                        ),
                                      ),
                                    ],
                                    titlesData: FlTitlesData(
                                      bottomTitles: AxisTitles(
                                        sideTitles: SideTitles(
                                          showTitles: true,
                                          reservedSize: 28,
                                          interval: 1,
                                          getTitlesWidget: (value, meta) {
                                            // keep existing labels logic
                                            final daysWithData =
                                                monthlySpots
                                                    .map((e) => e.x.toInt())
                                                    .toSet();
                                            if (!daysWithData.contains(
                                              value.toInt(),
                                            )) {
                                              return const SizedBox();
                                            }
                                            return SideTitleWidget(
                                              meta: meta,
                                              child: Text(
                                                value.toInt().toString(),
                                                style: const TextStyle(
                                                  fontSize: 10,
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                      // keep ylabel logic unchanged
                                      leftTitles: AxisTitles(
                                        sideTitles: SideTitles(
                                          showTitles: true,
                                          reservedSize: 54,
                                          interval: 1,
                                          getTitlesWidget: (value, meta) {
                                            if (isPlank) {
                                              if (effectiveFilter ==
                                                  GraphFilter.accuracy) {
                                                final v = value.toInt();
                                                const ticks = {
                                                  0,
                                                  20,
                                                  40,
                                                  60,
                                                  80,
                                                  100,
                                                };
                                                if (!ticks.contains(v)) {
                                                  return const SizedBox();
                                                }
                                                return SideTitleWidget(
                                                  meta: meta,
                                                  child: Text(
                                                    '$v%',
                                                    style: const TextStyle(
                                                      fontSize: 10,
                                                    ),
                                                  ),
                                                );
                                              } else {
                                                const labels = [
                                                  '0s',
                                                  '1s-10s',
                                                  '11s-20s',
                                                  '21s-35s',
                                                  '36s-50s',
                                                  '51s-60s',
                                                  '61s-75s',
                                                  '76s-85s',
                                                  '86s-90s',
                                                ];
                                                int index = value.toInt();
                                                if (index < 0 ||
                                                    index >= labels.length) {
                                                  return const SizedBox();
                                                }
                                                return SideTitleWidget(
                                                  meta: meta,
                                                  child: Text(
                                                    labels[index],
                                                    style: const TextStyle(
                                                      fontSize: 10,
                                                    ),
                                                  ),
                                                );
                                              }
                                            } else if (selectedFilter ==
                                                GraphFilter.accuracy) {
                                              final v = value.toInt();
                                              const ticks = {
                                                0,
                                                20,
                                                40,
                                                60,
                                                80,
                                                100,
                                              };
                                              if (!ticks.contains(v)) {
                                                return const SizedBox();
                                              }
                                              return SideTitleWidget(
                                                meta: meta,
                                                child: Text(
                                                  '$v%',
                                                  style: const TextStyle(
                                                    fontSize: 10,
                                                  ),
                                                ),
                                              );
                                            } else if (selectedFilter ==
                                                GraphFilter.sets) {
                                              const labels = [
                                                '0-5',
                                                '6-10',
                                                '11-15',
                                                '16-20',
                                                '21-30',
                                                '31-40',
                                                '41-50',
                                              ];
                                              int index = value.toInt();
                                              if (index < 0 ||
                                                  index >= labels.length) {
                                                return const SizedBox();
                                              }
                                              return SideTitleWidget(
                                                meta: meta,
                                                child: Text(
                                                  labels[index],
                                                  style: const TextStyle(
                                                    fontSize: 10,
                                                  ),
                                                ),
                                              );
                                            } else {
                                              const labels = [
                                                '0',
                                                '1-4',
                                                '5-8',
                                                '9-12',
                                                '13-16',
                                                '17-20',
                                                '21-24',
                                                '25-28',
                                                '29-32',
                                                '33-36',
                                                '37-40',
                                              ];
                                              int index = value.toInt();
                                              if (index < 0 ||
                                                  index >= labels.length) {
                                                return const SizedBox();
                                              }
                                              return SideTitleWidget(
                                                meta: meta,
                                                child: Text(
                                                  labels[index],
                                                  style: const TextStyle(
                                                    fontSize: 10,
                                                  ),
                                                ),
                                              );
                                            }
                                          },
                                        ),
                                      ),
                                      topTitles: AxisTitles(
                                        sideTitles: SideTitles(
                                          showTitles: false,
                                        ),
                                      ),
                                      rightTitles: AxisTitles(
                                        sideTitles: SideTitles(
                                          showTitles: false,
                                        ),
                                      ),
                                    ),

                                    // NEW: align horizontal grid with Y-axis labels
                                    gridData: FlGridData(
                                      show: true,
                                      drawVerticalLine: true,
                                      horizontalInterval:
                                          isPlank
                                              ? (effectiveFilter ==
                                                      GraphFilter.accuracy
                                                  ? 20
                                                  : 1)
                                              : (selectedFilter ==
                                                      GraphFilter.accuracy
                                                  ? 20
                                                  : 1),
                                      getDrawingHorizontalLine:
                                          (v) => FlLine(
                                            color: Colors.grey.shade200,
                                            strokeWidth: 1,
                                          ),
                                      getDrawingVerticalLine:
                                          (v) => FlLine(
                                            color: Colors.grey.shade200,
                                            strokeWidth: 1,
                                          ),
                                    ),

                                    borderData: FlBorderData(
                                      show: true,
                                      border: Border.all(
                                        color: Colors.black,
                                        width: 1,
                                      ),
                                    ),
                                  ),
                                ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
      ],
    );
  }

  Widget _statItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w500,
            color: color,
          ),
        ),
      ],
    );
  }
}

// NEW: helper function to compute form accuracy
// Returns percentage; safe for attemptedReps == 0.
double formAccuracy(int correctReps, int attemptedReps) {
  if (attemptedReps <= 0) return 0.0;
  return (correctReps / attemptedReps) * 100.0;
}
