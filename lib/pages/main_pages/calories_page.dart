// ignore_for_file: avoid_print

import 'package:flutter/material.dart';
import '/components/appbar.dart';
import '/components/calorie_search.dart';
import '/components/navbar.dart';
import '/components/update_calories.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
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

  int _selectedIndex = 0;
  double minCalories = 1500;
  double maxCalories = 3000;

  DateTime get _today => DateTime.now();
  DateTime get _startOfWeek =>
      _today.subtract(Duration(days: _today.weekday)); // Sunday
  DateTime get _startOfMonth =>
      DateTime(_today.year, _today.month, 1); // First day of current month

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
            ToggleButtons(
              isSelected: [
                _selectedIndex == 0,
                _selectedIndex == 1,
                _selectedIndex == 2,
              ],
              onPressed: (index) {
                setState(() {
                  _selectedIndex = index;
                });
              },
              borderRadius: BorderRadius.circular(12),
              selectedColor: Colors.white,
              fillColor: const Color.fromARGB(255, 0, 215, 248),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text("Day", style: GoogleFonts.poppins()),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text("Week", style: GoogleFonts.poppins()),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text("Month", style: GoogleFonts.poppins()),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Stream for calorie logs with date range filter
            StreamBuilder<QuerySnapshot>(
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

                final logs = snapshot.data!.docs;
                final totalCalories = logs.fold(
                  0.0,
                  (add, log) => add + (log['calories'] ?? 0),
                );

                return Column(
                  children: [
                    Text(
                      "Total Calories: ${totalCalories.toStringAsFixed(2)} kcal",
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value:
                          totalCalories.clamp(0.0, maxCalories) / maxCalories,
                      backgroundColor: Colors.grey.shade300,
                      color: const Color.fromARGB(255, 0, 215, 248),
                      minHeight: 16,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "Min: ${minCalories.toInt()}",
                          style: GoogleFonts.poppins(fontSize: 14),
                        ),
                        Text(
                          "Max: ${maxCalories.toInt()}",
                          style: GoogleFonts.poppins(fontSize: 14),
                        ),
                      ],
                    ),
                    const SizedBox(height: 30),
                  ],
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

                  final logs = snapshot.data!.docs;

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
                        DateTime dateTime = DateTime.parse('$rawDate $rawTime');
                        formattedDate = DateFormat.yMMMMd().format(
                          dateTime,
                        ); // e.g., April 5, 2025
                        formattedTime = DateFormat.jm().format(
                          dateTime,
                        ); // e.g., 12:30 PM
                      } catch (_) {
                        // fallback in case of format errors
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
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      food,
                                      style: GoogleFonts.poppins(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    Text(
                                      formattedDate,
                                      style: GoogleFonts.poppins(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w400,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      "$calories kcal",
                                      style: GoogleFonts.poppins(
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                    Text(
                                      formattedTime,
                                      style: GoogleFonts.poppins(
                                        color: Colors.grey.shade600,
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
        backgroundColor: const Color.fromARGB(255, 0, 215, 248),
        child: Icon(Icons.add),
      ),
      bottomNavigationBar: const NavBar(currentIndex: 2),
    );
  }
}
