import '/progress/progress_tracker.dart';
import 'package:flutter/material.dart';
import '/components/appbar.dart';
import '/components/navbar.dart';
import '/analytics/analytics.dart';

class WorkoutPage extends StatelessWidget {
  const WorkoutPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const Header(),

      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 16),
          physics: const BouncingScrollPhysics(),
          child: Column(
            children: const [
              SizedBox(height: 8),
              Analytics(),
              SizedBox(height: 8),
              ProgressTracker(workoutData: {}),
            ],
          ),
        ),
      ),

      bottomNavigationBar: const NavBar(currentIndex: 1),
    );
  }
}
