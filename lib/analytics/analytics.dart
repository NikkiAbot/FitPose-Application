import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '/analytics/presentation/app_resources.dart';
import '/analytics/modules/line_chart_widget.dart';
import '/analytics/modules/chart_legend.dart';

class Analytics extends StatefulWidget {
  const Analytics({super.key});

  @override
  State<StatefulWidget> createState() => AnalyticsState();
}

class AnalyticsState extends State<Analytics> {
  late bool isShowingMainData;
  List<int> activeWorkoutIndices = [
    0,
    1,
    2,
    3,
    4,
    5,
  ]; // All workouts active by default

  @override
  void initState() {
    super.initState();
    isShowingMainData = true;
  }

  void _updateActiveFilters(List<int> activeIndices) {
    setState(() {
      activeWorkoutIndices = activeIndices;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1.20,
      child: Stack(
        children: <Widget>[
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const SizedBox(height: 10),
              Text(
                'Workout Posture Accuracy',
                style: GoogleFonts.poppins(
                  color: AppColors.primary,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios, size: 16),
                    onPressed: () {
                      setState(() {
                        // Handle previous month logic here
                      });
                    },
                  ),

                  // Navigate to different months
                  Text(
                    'May 2025', // This will be dynamic based on selected month
                    style: GoogleFonts.poppins(
                      color: Colors.grey,
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  IconButton(
                    icon: const Icon(Icons.arrow_forward_ios, size: 16),
                    onPressed:
                        DateTime.now().month == 5 && DateTime.now().year == 2025
                            ? null // Disable if current month is the present
                            : () {
                              setState(() {
                                // Handle next month logic here
                              });
                            },
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 30, left: 10),
                  child: LineChartWidget(
                    isShowingMainData: isShowingMainData,
                    activeIndices: activeWorkoutIndices,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              ChartLegend(
                onFiltersChanged: _updateActiveFilters,
                initialActiveIndices: activeWorkoutIndices,
              ),
              const SizedBox(height: 10),
            ],
          ),
          Positioned(
            top: 33,
            right: 10,
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
        ],
      ),
    );
  }
}
