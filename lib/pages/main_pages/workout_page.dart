import 'package:flutter/material.dart';
import '/components/appbar.dart';
import '/components/navbar.dart';
import '../../workouts_analytics/combined_analytics_progress.dart';

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
            children: [
              const SizedBox(height: 8),
              CombinedAnalyticsProgress(workoutData: {}),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),

      bottomNavigationBar: const NavBar(currentIndex: 1),
    );
  }
}
