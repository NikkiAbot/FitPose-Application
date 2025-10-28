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

enum GraphFilter { reps, sets }

class _WorkoutAnalyticsWidgetState extends State<WorkoutAnalyticsWidget> {
  DateTime selectedDate = DateTime.now();

  // Totals
  int dailyReps = 0;
  int dailySets = 0;
  int dailyDuration = 0;

  int totalReps = 0;
  int totalSets = 0;
  int totalDuration = 0;

  bool isLoading = true;

  // Graph
  List<FlSpot> monthlySpots = [];
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
    List<FlSpot> tempSpots = [];
    int tempMax = 0;

    final isPlank = widget.exercise.toLowerCase() == 'plank';

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

        tr += reps;
        ts += sets;
        if (_isSameDate(date, selectedDate)) {
          dr += reps;
          ds += sets;
        }

        // Graph: reps/sets
        if (date.year == selectedDate.year &&
            date.month == selectedDate.month) {
          final value = selectedFilter == GraphFilter.reps ? reps : sets;
          tempSpots.add(FlSpot(date.day.toDouble(), value.toDouble()));
          if (value > tempMax) tempMax = value;
        }
      } else {
        // Graph: duration only
        if (date.year == selectedDate.year &&
            date.month == selectedDate.month) {
          // Map duration to Y-axis index (custom ranges)
          int yIndex = _getPlankYIndex(duration);
          tempSpots.add(FlSpot(date.day.toDouble(), yIndex.toDouble()));
          if (yIndex > tempMax) tempMax = yIndex;
        }
      }
    }

    setState(() {
      dailyReps = dr;
      dailySets = ds;
      dailyDuration = dd;

      totalReps = tr;
      totalSets = ts;
      totalDuration = td;

      monthlySpots = tempSpots;
      maxY = isPlank ? 8 : 10; // 9 labels for plank (0-8)
      isLoading = false;
    });
  }

  // Map actual duration in seconds to Y-axis index
  int _getPlankYIndex(int seconds) {
    if (seconds == 0) return 0;
    if (seconds <= 10) return 1;
    if (seconds <= 20) return 2;
    if (seconds <= 35) return 3;
    if (seconds <= 50) return 4;
    if (seconds <= 60) return 5;
    if (seconds <= 75) return 6;
    if (seconds <= 85) return 7;
    return 8;
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

    return Column(
      children: [
        // Date picker
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.blueGrey.shade50,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.blueGrey.shade200),
                ),
                child: Text(
                  DateFormat.yMMMMd().format(selectedDate),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(
                  Icons.calendar_today,
                  color: Colors.blueGrey,
                  size: 20,
                ),
                onPressed: () => _pickDate(context),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        isLoading
            ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
            : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Workout Totals',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Card(
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          color: Colors.green.shade50,
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              children: [
                                Text(
                                  'Daily Totals',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green.shade800,
                                  ),
                                ),
                                const Divider(thickness: 1, height: 12),
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
                      const SizedBox(width: 8),
                      Expanded(
                        child: Card(
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          color: Colors.grey.shade50,
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              children: [
                                Text(
                                  'Overall Totals',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black87,
                                  ),
                                ),
                                const Divider(thickness: 1, height: 12),
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
                  const SizedBox(height: 16),
                  // Graph Label + Filter
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Monthly Data',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      if (!isPlank)
                        ToggleButtons(
                          isSelected: [
                            selectedFilter == GraphFilter.reps,
                            selectedFilter == GraphFilter.sets,
                          ],
                          onPressed: (index) {
                            _changeFilter(
                              index == 0 ? GraphFilter.reps : GraphFilter.sets,
                            );
                          },
                          borderRadius: BorderRadius.circular(6),
                          selectedColor: Colors.white,
                          fillColor: Colors.blue,
                          color: Colors.blue,
                          children: const [
                            Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              child: Text(
                                'Reps',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                            Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              child: Text(
                                'Sets',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 200,
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
                                lineBarsData: [
                                  LineChartBarData(
                                    spots: monthlySpots,
                                    isCurved: true,
                                    color: Colors.blue,
                                    barWidth: 2.5,
                                    dotData: FlDotData(show: true),
                                  ),
                                ],
                                titlesData: FlTitlesData(
                                  bottomTitles: AxisTitles(
                                    sideTitles: SideTitles(
                                      showTitles: true,
                                      reservedSize: 28,
                                      interval:
                                          1, // use 1, since we control which days to show
                                      getTitlesWidget: (value, meta) {
                                        // Only show days that exist in monthlySpots
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

                                  leftTitles: AxisTitles(
                                    sideTitles: SideTitles(
                                      showTitles: true,
                                      reservedSize: 50,
                                      interval: 1,
                                      getTitlesWidget: (value, meta) {
                                        if (isPlank) {
                                          const labels = [
                                            '0',
                                            '1-10 s',
                                            '11-20',
                                            '21-35',
                                            '36-50',
                                            '51-60',
                                            '61-75',
                                            '76-85',
                                            '86-90',
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
                                    sideTitles: SideTitles(showTitles: false),
                                  ),
                                  rightTitles: AxisTitles(
                                    sideTitles: SideTitles(showTitles: false),
                                  ),
                                ),
                                gridData: FlGridData(show: true),
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
