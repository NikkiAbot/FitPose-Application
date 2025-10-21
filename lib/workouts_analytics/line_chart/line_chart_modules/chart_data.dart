import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../presentation/app_resources.dart';
import 'chart_titles.dart';

class ChartData {
  // Inside the ChartData class
  static LineChartData sampleData1(
    BuildContext context,
    List<int> activeIndices,
    List<LineChartBarData> allBars, // <- now provided by caller
  ) => LineChartData(
    lineTouchData: _lineTouchData1(context, activeIndices),
    gridData: _gridData,
    titlesData: ChartTitles.titlesData1,
    borderData: _borderData,
    lineBarsData: _getFilteredLineBarsData(allBars, activeIndices),
    minX: 0,
    maxX: 14,
    maxY: 100,
    minY: 0,
  );

  static LineChartData sampleData2(
    BuildContext context,
    List<int> activeIndices,
    List<LineChartBarData> allBars, // <- now provided by caller
  ) => LineChartData(
    lineTouchData: _lineTouchData2,
    gridData: _gridData,
    titlesData: ChartTitles.titlesData2,
    borderData: _borderData,
    lineBarsData: _getFilteredLineBarsData(allBars, activeIndices),
    minX: 0,
    maxX: 14,
    maxY: 100,
    minY: 0,
  );

  // Add this helper method
  static List<LineChartBarData> _getFilteredLineBarsData(
    List<LineChartBarData> allData,
    List<int> activeIndices,
  ) {
    final List<LineChartBarData> filteredData = [];
    for (int i = 0; i < allData.length; i++) {
      if (activeIndices.contains(i)) {
        filteredData.add(allData[i]);
      }
    }
    return filteredData;
  }

  static LineTouchData _lineTouchData1(
    BuildContext context,
    List<int> activeIndices,
  ) => LineTouchData(
    handleBuiltInTouches: false, // Disable default tooltips
    touchCallback: (FlTouchEvent event, LineTouchResponse? touchResponse) {
      if (event is FlTapUpEvent &&
          touchResponse?.lineBarSpots != null &&
          touchResponse!.lineBarSpots!.isNotEmpty) {
        final spot = touchResponse.lineBarSpots!.first;
        final filteredIndex = spot.barIndex;

        // Map the filtered index back to the actual workout index
        final actualWorkoutIndex =
            activeIndices.length > filteredIndex
                ? activeIndices[filteredIndex]
                : -1;

        String workoutType = "";
        switch (actualWorkoutIndex) {
          case 0:
            workoutType = 'Squat';
            break;
          case 1:
            workoutType = 'Plank';
            break;
          case 2:
            workoutType = 'Push Up';
            break;
          case 3:
            workoutType = 'Shoulder Press';
            break;
          case 4:
            workoutType = 'Bicep Curl';
            break;
          case 5:
            workoutType = 'Lunges';
            break;
          default:
            workoutType = 'Unknown';
        }

        final accuracy = spot.y.toInt();

        // Simple dialog showing workout and accuracy (removed calendar mapping)
        showDialog(
          context: context,
          builder:
              (ctx) => AlertDialog(
                title: Text(workoutType),
                content: Text('Accuracy: $accuracy'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('OK'),
                  ),
                ],
              ),
        );
      }
    },
    touchTooltipData: LineTouchTooltipData(
      tooltipPadding: EdgeInsets.zero,
      tooltipMargin: 8,
      getTooltipItems: (_) => [],
    ),
  );

  static LineTouchData get _lineTouchData2 =>
      const LineTouchData(enabled: false);

  static FlGridData get _gridData => FlGridData(
    show: true,
    drawVerticalLine: false,
    horizontalInterval: 20,
    getDrawingHorizontalLine:
        (value) => FlLine(color: Colors.grey.withAlpha(77), strokeWidth: 1),
  );

  static FlBorderData get _borderData => FlBorderData(
    show: true,
    border: Border(
      bottom: BorderSide(color: AppColors.primary.withAlpha(51), width: 4),
      left: BorderSide(color: Colors.grey.withAlpha(51)),
      right: const BorderSide(color: Colors.transparent),
      top: const BorderSide(color: Colors.transparent),
    ),
  );
}
