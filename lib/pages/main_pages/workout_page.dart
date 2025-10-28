import 'package:fitpose/components/analytics.dart';
import 'package:flutter/material.dart';
import '/components/appbar.dart';
import '/components/navbar.dart';

class WorkoutPage extends StatefulWidget {
  const WorkoutPage({super.key});

  @override
  State<WorkoutPage> createState() => _WorkoutPageState();
}

class _WorkoutPageState extends State<WorkoutPage> {
  // Current selected exercise
  String selectedExercise = 'pushup';

  final List<String> exercises = [
    'pushup',
    'squat',
    'plank',
    'bicep',
    'shoulderpress',
    'lunges',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const Header(),

      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 16),
          physics: const BouncingScrollPhysics(),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 20.0,
                ),
                child: Center(
                  child: Text(
                    'Workout Analytics',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),

              // Analytics widget for the selected exercise
              WorkoutAnalyticsWidget(exercise: selectedExercise),
              const SizedBox(height: 16),

              // Exercise filter buttons
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children:
                        exercises.map((exercise) {
                          final isSelected = exercise == selectedExercise;
                          return Padding(
                            padding: const EdgeInsets.only(right: 8.0),
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor:
                                    isSelected
                                        ? Colors.blue
                                        : Colors.grey.shade200,
                                foregroundColor:
                                    isSelected ? Colors.white : Colors.black87,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                              ),
                              onPressed: () {
                                setState(() {
                                  selectedExercise = exercise;
                                });
                              },
                              child: Text(
                                exercise[0].toUpperCase() +
                                    exercise.substring(1),
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                  ),
                ),
              ),

              const SizedBox(height: 16),
            ],
          ),
        ),
      ),

      bottomNavigationBar: const NavBar(currentIndex: 1),
    );
  }
}
