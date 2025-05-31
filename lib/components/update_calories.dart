import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class CalorieUpdate extends StatefulWidget {
  final String docId;
  final String initialFood; // Add this parameter
  final int initialCalories;
  final String initialDate;
  final String initialTime;
  final Map<String, dynamic> existingData;

  const CalorieUpdate({
    super.key,
    required this.docId,
    required this.initialFood, // Add this parameter
    required this.initialCalories,
    required this.initialDate,
    required this.initialTime,
    required this.existingData,
  });

  @override
  State<CalorieUpdate> createState() => _CalorieUpdateState();
}

class _CalorieUpdateState extends State<CalorieUpdate> {
  final TextEditingController searchController = TextEditingController();
  final TextEditingController dateController = TextEditingController();
  final TextEditingController timeController = TextEditingController();

  List<dynamic> searchResults = [];
  Map<String, dynamic>? selectedFood;
  bool isSearching = false;

  get selectedDate => null;

  @override
  void initState() {
    super.initState();

    searchController.text = widget.existingData['food'];
    dateController.text = widget.existingData['date'];
    timeController.text = widget.existingData['time'];

    // Initialize selectedFood with the existing data manually
    selectedFood = {
      'description': widget.existingData['food'],
      'foodNutrients': [
        {
          'nutrientName': 'Energy',
          'unitName': 'KCAL',
          'value': widget.existingData['calories'],
        },
      ],
    };
  }

  Future<List<dynamic>> searchFood() async {
    try {
      final response = await http.post(
        Uri.parse(
          "https://api.nal.usda.gov/fdc/v1/foods/search?api_key=KGNooTXUxdwG2I77l5AYAyDBLZU8firI8fEoAl5U",
        ),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"query": searchController.text, "pageSize": 5}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['foods'] ?? [];
      } else {
        if (kDebugMode) {
          print('API Error: ${response.statusCode} - ${response.body}');
        }
        return [];
      }
    } catch (e) {
      if (kDebugMode) {
        print('Exception during API call: $e');
      }
      return [];
    }
  }

  Future<void> pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      dateController.text = picked.toIso8601String().split("T").first;
    }
  }

  Future<void> pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (picked != null && mounted) {
      timeController.text = picked.format(context);
    }
  }

  void updateLog() async {
    final nutrients = selectedFood?['foodNutrients'] ?? [];
    final energy = nutrients.firstWhere(
      (n) => n['nutrientName'] == 'Energy' && n['unitName'] == 'KCAL',
      orElse: () => null,
    );

    final updateData = {
      'food': selectedFood!['description'],
      'calories': energy != null ? energy['value'] : 0,
      'date': dateController.text,
      'time': timeController.text,
      'timestamp': FieldValue.serverTimestamp(),
    };

    await FirebaseFirestore.instance
        .collection('calorie_logs')
        .doc(widget.docId)
        .update(updateData);

    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Log updated successfully!',
            style: GoogleFonts.poppins(),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text("Update Your Logs", style: GoogleFonts.poppins()),
      content: SingleChildScrollView(
        child: Column(
          children: [
            Text(
              "Food:",
              style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
            ),
            GestureDetector(
              onTap: () {
                // Search for new food
                showDialog(
                  context: context,
                  builder:
                      (_) => StatefulBuilder(
                        // Use StatefulBuilder to update dialog content
                        builder:
                            (context, setDialogState) => Dialog(
                              child: Container(
                                padding: const EdgeInsets.all(16),
                                constraints: BoxConstraints(
                                  maxWidth:
                                      MediaQuery.of(context).size.width * 0.9,
                                  maxHeight:
                                      MediaQuery.of(context).size.height * 0.8,
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      "Search for new food",
                                      style: GoogleFonts.poppins(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    TextField(
                                      controller: searchController,
                                      decoration: const InputDecoration(
                                        hintText: "Enter food name",
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    ElevatedButton(
                                      onPressed: () async {
                                        setDialogState(
                                          () => isSearching = true,
                                        ); // Update dialog state
                                        final results = await searchFood();
                                        setDialogState(() {
                                          searchResults = results;
                                          isSearching = false;
                                        }); // Update dialog with search results
                                      },
                                      child: Text(
                                        "Search",
                                        style: GoogleFonts.poppins(),
                                      ),
                                    ),
                                    if (isSearching)
                                      const Center(
                                        child: CircularProgressIndicator(),
                                      ),
                                    if (!isSearching &&
                                        searchResults.isNotEmpty)
                                      Expanded(
                                        child: ListView.builder(
                                          shrinkWrap: true,
                                          itemCount: searchResults.length,
                                          itemBuilder: (context, index) {
                                            final food = searchResults[index];
                                            final description =
                                                food['description'];
                                            final nutrients =
                                                food['foodNutrients']
                                                    as List<dynamic>;
                                            final kcal = nutrients.firstWhere(
                                              (n) =>
                                                  n['nutrientName'] ==
                                                      'Energy' &&
                                                  n['unitName'] == 'KCAL',
                                              orElse: () => {'value': 0},
                                            );

                                            return ListTile(
                                              title: Text(
                                                description,
                                                style: GoogleFonts.poppins(),
                                              ),
                                              subtitle: Text(
                                                "${kcal['value']} kcal",
                                                style: GoogleFonts.poppins(
                                                  color: Colors.grey,
                                                ),
                                              ),
                                              onTap: () {
                                                setState(() {
                                                  selectedFood = food;
                                                  searchController.text =
                                                      description;
                                                });
                                                Navigator.pop(context);
                                              },
                                            );
                                          },
                                        ),
                                      ),
                                    const SizedBox(height: 8),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        TextButton(
                                          onPressed:
                                              () => Navigator.pop(context),
                                          child: Text(
                                            "Cancel",
                                            style: GoogleFonts.poppins(),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                      ),
                );
              },
              child: Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade400),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        selectedFood?['description'] ?? "Select Food",
                        style: GoogleFonts.poppins(),
                      ),
                    ),
                    const Icon(Icons.edit),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              "Calories: ${selectedFood?['foodNutrients']?[0]?['value'] ?? 0} kcal",
              style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: dateController,
              readOnly: true,
              onTap: pickDate,
              decoration: const InputDecoration(labelText: "Date"),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: timeController,
              readOnly: true,
              onTap: pickTime,
              decoration: const InputDecoration(labelText: "Time"),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text("Cancel", style: GoogleFonts.poppins()),
        ),
        ElevatedButton(
          onPressed: updateLog,
          child: Text("Update", style: GoogleFonts.poppins()),
        ),
      ],
    );
  }
}
