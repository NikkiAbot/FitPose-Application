import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';

class CalorieSearch extends StatefulWidget {
  const CalorieSearch({super.key});

  @override
  State<CalorieSearch> createState() => _CalorieSearchState();
}

class _CalorieSearchState extends State<CalorieSearch> {
  final TextEditingController searchController = TextEditingController();
  final TextEditingController dateController = TextEditingController();
  final TextEditingController timeController = TextEditingController();

  List<dynamic> searchResults = [];
  Map<String, dynamic>? selectedFood;
  bool isLoading = false;

  get selectedDate => null;

  Future<void> searchFood() async {
    setState(() => isLoading = true);
    final query = searchController.text;

    final response = await http.post(
      Uri.parse(
        "https://api.nal.usda.gov/fdc/v1/foods/search?api_key=KGNooTXUxdwG2I77l5AYAyDBLZU8firI8fEoAl5U",
      ),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({"query": query, "pageSize": 5}),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      setState(() {
        searchResults = data['foods'] ?? [];
      });
    }

    setState(() => isLoading = false);
  }

  Future<void> pickDate() async {
    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
    );
    if (pickedDate != null) {
      setState(() {
        dateController.text = pickedDate.toIso8601String().split('T').first;
      });
    }
  }

  Future<void> pickTime() async {
    final TimeOfDay? pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (pickedTime != null) {
      setState(() {
        timeController.text = pickedTime.format(context);
      });
    }
  }

  // Function to show feedback Snackbar
  void showFeedback(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message, style: GoogleFonts.poppins())),
    );
  }

  @override
  Widget build(BuildContext context) {
    // POP UP DIALOG
    return AlertDialog(
      title: Text("Log Calorie Intake", style: GoogleFonts.poppins()),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("Search for a food item:", style: GoogleFonts.poppins()),
            const SizedBox(height: 10),
            TextField(
              controller: searchController,
              decoration: const InputDecoration(
                hintText: "e.g., Cheddar Cheese",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),

            // AFTER FOOD HAS BEEN SEARCHED
            ElevatedButton(
              onPressed: searchFood,
              child: Text("Search", style: GoogleFonts.poppins()),
            ),
            if (isLoading) const CircularProgressIndicator(),
            if (!isLoading && searchResults.isNotEmpty)
              ...searchResults.map((food) {
                final description = food['description'];
                final kcal = (food['foodNutrients'] as List<dynamic>)
                    .firstWhere(
                      (n) =>
                          n['nutrientName'] == 'Energy' &&
                          n['unitName'] == 'KCAL',
                      orElse: () => null,
                    );

                return ListTile(
                  title: Text(
                    description,
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
                  ),
                  subtitle: Text(
                    kcal != null ? "${kcal['value']} kcal" : "No kcal info",
                    style: GoogleFonts.poppins(color: Colors.grey),
                  ),
                  onTap: () {
                    setState(() {
                      selectedFood = food;
                    });
                  },
                );
              }),

            // AFTER FOOD HAS BEEN SELECTED
            if (selectedFood != null) ...[
              const Divider(),
              Text(
                "Selected: ${selectedFood!['description']}",
                style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: dateController,
                readOnly: true,
                decoration: const InputDecoration(
                  labelText: "Date",
                  border: OutlineInputBorder(),
                ),
                onTap: pickDate,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: timeController,
                readOnly: true,
                decoration: const InputDecoration(
                  labelText: "Time",
                  border: OutlineInputBorder(),
                ),
                onTap: pickTime,
              ),
              const SizedBox(height: 10),
              ElevatedButton.icon(
                icon: const Icon(Icons.add),
                label: Text("Add Calories", style: GoogleFonts.poppins()),
                onPressed: () async {
                  final nutrients =
                      selectedFood!['foodNutrients'] as List<dynamic>;
                  final energy = nutrients.firstWhere(
                    (n) =>
                        n['nutrientName'] == 'Energy' &&
                        n['unitName'] == 'KCAL',
                    orElse: () => null,
                  );

                  // Save the log to Firestore
                  final logData = {
                    "food": selectedFood!['description'],
                    "calories": energy != null ? energy['value'] : 0,
                    "date": dateController.text,
                    "time": timeController.text,
                    "timestamp": FieldValue.serverTimestamp(),
                    "userId":
                        FirebaseAuth
                            .instance
                            .currentUser
                            ?.uid, // Storing the userId
                  };

                  await FirebaseFirestore.instance
                      .collection('calorie_logs')
                      .add(logData);

                  showFeedback(
                    "Calorie intake logged successfully!",
                  ); // Show success message
                  if (context.mounted) Navigator.pop(context);
                },
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text("Close", style: GoogleFonts.poppins()),
        ),
      ],
    );
  }
}
