// ignore_for_file: avoid_print

import 'package:flutter/material.dart';
import '/components/appbar.dart';
import '../../components/calorie_widgets/calorie_search.dart';
import '/components/navbar.dart';
import '../../components/calorie_widgets/update_calories.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_auth/firebase_auth.dart';

class Calories extends StatefulWidget {
  const Calories({super.key});

  @override
  State<Calories> createState() => _CaloriesState();
}

class FirestoreService {
  final CollectionReference logs = FirebaseFirestore.instance.collection(
    'logs',
  );
}

class _CaloriesState extends State<Calories> {
  final FirestoreService firestoreService = FirestoreService();

  int _selectedIndex = 0; // 0=Day,1=Week,2=Month
  static const double _defaultDailyGoal = 2000.0;

  DateTime get _today => DateTime.now();
  DateTime get _startOfWeek =>
      _today.subtract(Duration(days: _today.weekday)); // Sunday
  DateTime get _startOfMonth =>
      DateTime(_today.year, _today.month, 1); // First day of current month

  int get _periodDays {
    switch (_selectedIndex) {
      case 0:
        return 1; // Day
      case 1:
        return 7; // Week
      case 2:
        // Days in current month
        return DateTime(_today.year, _today.month + 1, 0).day;
      default:
        return 1;
    }
  }

  Future<void> _openGoalSheet(
    BuildContext context,
    double? currentDailyGoal,
  ) async {
    final controller = TextEditingController(
      text: (currentDailyGoal ?? _defaultDailyGoal).toStringAsFixed(0),
    );
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Set Daily Calorie Goal',
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Daily goal (kcal)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    final val = double.tryParse(controller.text.trim());
                    if (val == null || val <= 0) {
                      Navigator.of(ctx).pop();
                      return;
                    }
                    final uid = FirebaseAuth.instance.currentUser?.uid;
                    if (uid != null) {
                      await FirebaseFirestore.instance
                          .collection('user_settings')
                          .doc(uid)
                          .set({
                            'dailyCalorieGoal': val,
                          }, SetOptions(merge: true));
                    }
                    if (context.mounted) Navigator.of(ctx).pop();
                  },
                  child: Text('Save', style: GoogleFonts.poppins()),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openCalorieInfo() async {
    const url = 'https://blog.myfitnesspal.com/how-to-calculate-caloric-needs/';
    final uri = Uri.parse(url);
    try {
      // Prefer external browser; fall back to in-app browser view and platform default
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
      if (await launchUrl(uri, mode: LaunchMode.inAppBrowserView)) return;
      if (await launchUrl(uri, mode: LaunchMode.platformDefault)) return;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Could not open the link. Please ensure a default browser is installed.',
              style: GoogleFonts.poppins(),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to launch browser: $e',
              style: GoogleFonts.poppins(),
            ),
          ),
        );
      }
    }
  }

  Widget _buildPeriodSelector() {
    final labels = ['Day', 'Week', 'Month'];
    return Wrap(
      spacing: 8,
      children: List.generate(labels.length, (i) {
        final selected = _selectedIndex == i;
        return ChoiceChip(
          label: Text(
            labels[i],
            style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
          ),
          selected: selected,
          onSelected: (_) => setState(() => _selectedIndex = i),
          selectedColor: const Color.fromARGB(255, 0, 215, 248),
          backgroundColor: Colors.grey.shade200,
          labelStyle: GoogleFonts.poppins(
            color: selected ? Colors.white : Colors.black87,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        );
      }),
    );
  }

  Color _progressColor(double pct) {
    if (pct < 0.5) return const Color(0xFF00C4D8);
    if (pct < 0.85) return const Color(0xFF00D7F8);
    return Colors.redAccent;
  }

  Widget _headerSummary({
    required double totalCalories,
    required double periodGoal,
    required double dailyGoal,
  }) {
    final pct =
        periodGoal > 0 ? (totalCalories / periodGoal).clamp(0.0, 1.0) : 0.0;
    final remaining = (periodGoal - totalCalories).clamp(0, double.infinity);
    final avgPerDay = _periodDays > 0 ? (totalCalories / _periodDays) : 0.0;
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF04202B), Color(0xFF093A46), Color(0xFF0B4F59)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Total: ${totalCalories.toStringAsFixed(0)} / ${periodGoal.toStringAsFixed(0)} kcal',
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
              SizedBox(
                width: 60,
                height: 60,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: pct),
                      duration: const Duration(milliseconds: 600),
                      curve: Curves.easeOutQuart,
                      builder: (context, value, _) {
                        return CircularProgressIndicator(
                          value: value,
                          strokeWidth: 6,
                          backgroundColor: Colors.white12,
                          valueColor: AlwaysStoppedAnimation(
                            _progressColor(value),
                          ),
                        );
                      },
                    ),
                    Text(
                      '${(pct * 100).toStringAsFixed(0)}%',
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: pct),
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeOutCubic,
            builder: (context, value, _) {
              return ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(
                  value: value,
                  minHeight: 14,
                  backgroundColor: Colors.white10,
                  valueColor: AlwaysStoppedAnimation(_progressColor(value)),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              Text(
                ' • Remaining: ${remaining.toStringAsFixed(0)} kcal \n • Avg/Day: ${avgPerDay.toStringAsFixed(0)} kcal  \n • Daily Goal: ${dailyGoal.toStringAsFixed(0)} kcal',
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: Colors.white70,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Divider(color: Colors.white24, height: 1),
          const SizedBox(height: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: () => _openGoalSheet(context, dailyGoal),
                child: Text(
                  'change calorie goal',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    decoration: TextDecoration.underline,
                    color: Colors.lightBlueAccent,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              GestureDetector(
                onTap: _openCalorieInfo,
                child: Text(
                  'learn more about calorie targets',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    decoration: TextDecoration.underline,
                    color: Colors.lightBlueAccent,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // _statChip removed: stats condensed into a single line in the header.

  @override
  Widget build(BuildContext context) {
    // Get the current user
    User? currentUser = FirebaseAuth.instance.currentUser;

    // Check if the user is logged in
    if (currentUser == null) {
      return Scaffold(
        appBar: const Header(),
        body: Center(
          child: Text(
            "Please log in to see your logs.",
            style: GoogleFonts.poppins(fontSize: 16),
          ),
        ),
      );
    }

    print('Current user UID: ${currentUser.uid}'); // Debugging line

    // Calculate the start and end date based on the selected index (Day, Week, Month)
    late DateTime startDate;
    late DateTime endDate;

    switch (_selectedIndex) {
      case 0: // Day
        startDate = DateTime(_today.year, _today.month, _today.day);
        endDate = startDate.add(Duration(days: 1));
        break;
      case 1: // Week
        startDate = _startOfWeek;
        endDate = _startOfWeek.add(Duration(days: 7));
        break;
      case 2: // Month
        startDate = _startOfMonth;
        endDate = DateTime(
          _today.year,
          _today.month + 1,
          0,
        ); // Last day of the current month
        break;
      default:
        startDate = DateTime(_today.year, _today.month, _today.day);
        endDate = startDate.add(Duration(days: 1));
    }

    print("Start Date: $startDate");
    print("End Date: $endDate");

    return Scaffold(
      appBar: const Header(),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            _buildPeriodSelector(),

            const SizedBox(height: 20),

            // Stream for user goal, then stream logs and show progress
            StreamBuilder<DocumentSnapshot>(
              stream:
                  FirebaseFirestore.instance
                      .collection('user_settings')
                      .doc(currentUser.uid)
                      .snapshots(),
              builder: (context, goalSnap) {
                final goalData = goalSnap.data?.data() as Map<String, dynamic>?;
                final dailyGoal =
                    (goalData?['dailyCalorieGoal'] is num)
                        ? (goalData!['dailyCalorieGoal'] as num).toDouble()
                        : _defaultDailyGoal;
                final periodGoal = dailyGoal * _periodDays;

                return StreamBuilder<QuerySnapshot>(
                  stream:
                      FirebaseFirestore.instance
                          .collection('calorie_logs')
                          .where('userId', isEqualTo: currentUser.uid)
                          .where(
                            'date',
                            isGreaterThanOrEqualTo: DateFormat(
                              'yyyy-MM-dd',
                            ).format(startDate),
                          )
                          .where(
                            'date',
                            isLessThanOrEqualTo: DateFormat(
                              'yyyy-MM-dd',
                            ).format(endDate),
                          )
                          .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return Center(child: CircularProgressIndicator());
                    }

                    final logs = snapshot.data?.docs ?? [];
                    final totalCalories = logs.fold<double>(
                      0.0,
                      (add, log) =>
                          add + ((log['calories'] ?? 0) as num).toDouble(),
                    );

                    return Column(
                      children: [
                        _headerSummary(
                          totalCalories: totalCalories,
                          periodGoal: periodGoal,
                          dailyGoal: dailyGoal,
                        ),
                        const SizedBox(height: 26),
                      ],
                    );
                  },
                );
              },
            ),

            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                "Your Logs",
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

            const SizedBox(height: 10),

            // Stream for logs with the date range filter
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream:
                    FirebaseFirestore.instance
                        .collection('calorie_logs')
                        .where('userId', isEqualTo: currentUser.uid)
                        .where(
                          'date',
                          isGreaterThanOrEqualTo: DateFormat(
                            'yyyy-MM-dd',
                          ).format(startDate),
                        )
                        .where(
                          'date',
                          isLessThanOrEqualTo: DateFormat(
                            'yyyy-MM-dd',
                          ).format(endDate),
                        )
                        .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Center(child: CircularProgressIndicator());
                  }
                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return Center(
                      child: Text(
                        "No logs yet.",
                        style: GoogleFonts.poppins(fontSize: 16),
                      ),
                    );
                  }

                  // NEW: copy and sort by combined date+time descending
                  List<QueryDocumentSnapshot> logs =
                      List<QueryDocumentSnapshot>.from(snapshot.data!.docs);
                  DateTime parseDT(Map<String, dynamic> m) {
                    final ds = (m['date'] ?? '') as String;
                    final ts = (m['time'] ?? '') as String;
                    if (ds.isEmpty) return DateTime(1970);
                    try {
                      // Try full pattern
                      return DateFormat('yyyy-MM-dd h:mm a').parse('$ds $ts');
                    } catch (_) {
                      try {
                        return DateTime.parse(ds);
                      } catch (_) {
                        return DateTime(1970);
                      }
                    }
                  }

                  logs.sort((a, b) {
                    final ma = a.data() as Map<String, dynamic>;
                    final mb = b.data() as Map<String, dynamic>;
                    final da = parseDT(ma);
                    final db = parseDT(mb);
                    return db.compareTo(da); // desc
                  });

                  return ListView.builder(
                    itemCount: logs.length,
                    itemBuilder: (context, index) {
                      final log = logs[index].data() as Map<String, dynamic>;
                      final food = log['food'] ?? 'Unknown';
                      final calories = log['calories']?.toString() ?? '0';
                      final rawDate = log['date'] ?? '';
                      final rawTime = log['time'] ?? '';
                      String formattedDate = rawDate;
                      String formattedTime = rawTime;

                      try {
                        DateTime dateTime = DateFormat(
                          'yyyy-MM-dd h:mm a',
                        ).parse('$rawDate $rawTime');
                        formattedDate = DateFormat.yMMMMd().format(dateTime);
                        formattedTime = DateFormat.jm().format(dateTime);
                      } catch (_) {
                        try {
                          final dOnly = DateTime.parse(rawDate);
                          formattedDate = DateFormat.yMMMMd().format(dOnly);
                        } catch (_) {}
                      }

                      return GestureDetector(
                        onTap: () {
                          showDialog(
                            context: context,
                            builder: (context) {
                              return AlertDialog(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                title: Text(
                                  "Log Details",
                                  style: GoogleFonts.poppins(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                content: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      "Food: $food",
                                      style: GoogleFonts.poppins(),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      "Calories: $calories kcal",
                                      style: GoogleFonts.poppins(),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      "Date: $formattedDate",
                                      style: GoogleFonts.poppins(),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      "Time: $formattedTime",
                                      style: GoogleFonts.poppins(),
                                    ),
                                  ],
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () async {
                                      await FirebaseFirestore.instance
                                          .collection('calorie_logs')
                                          .doc(logs[index].id)
                                          .delete();
                                      // ignore: use_build_context_synchronously
                                      Navigator.of(context).pop();
                                    },
                                    child: Text(
                                      "Delete",
                                      style: GoogleFonts.poppins(
                                        color: Colors.red,
                                      ),
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: () {
                                      Navigator.of(context).pop();
                                    },
                                    child: Text(
                                      "Close",
                                      style: GoogleFonts.poppins(
                                        color: Colors.black,
                                      ),
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: () {
                                      Navigator.of(context).pop();
                                      showDialog(
                                        context: context,
                                        builder:
                                            (context) => CalorieUpdate(
                                              docId: logs[index].id,
                                              initialFood: food,
                                              initialCalories:
                                                  log['calories'] ?? 0,
                                              initialDate: rawDate,
                                              initialTime: rawTime,
                                              existingData: log,
                                            ),
                                      );
                                    },
                                    child: Text(
                                      "Update",
                                      style: GoogleFonts.poppins(
                                        color: Colors.blue,
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          );
                        },
                        child: Card(
                          elevation: 3,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        food,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: GoogleFonts.poppins(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: Align(
                                        alignment: Alignment.centerRight,
                                        child: Text(
                                          formattedDate,
                                          textAlign: TextAlign.right,
                                          overflow: TextOverflow.ellipsis,
                                          style: GoogleFonts.poppins(
                                            fontSize: 12, // smaller
                                            fontWeight: FontWeight.w400,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        "$calories kcal",
                                        overflow: TextOverflow.ellipsis,
                                        style: GoogleFonts.poppins(
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: Align(
                                        alignment: Alignment.centerRight,
                                        child: Text(
                                          formattedTime,
                                          textAlign: TextAlign.right,
                                          overflow: TextOverflow.ellipsis,
                                          style: GoogleFonts.poppins(
                                            fontSize: 12, // smaller
                                            color: Colors.grey.shade600,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          showDialog(context: context, builder: (context) => CalorieSearch());
        },
        // Slight transparency so underlying content hints remain visible.
        // Using ARGB with alpha < 255 instead of wrapping in Opacity to keep ripple effects.
        backgroundColor: const Color.fromARGB(200, 0, 215, 248), // ~78% opacity
        elevation: 6,
        splashColor: const Color.fromARGB(160, 0, 215, 248),
        child: const Icon(Icons.add, color: Colors.white),
      ),
      bottomNavigationBar: const NavBar(currentIndex: 2),
    );
  }
}
