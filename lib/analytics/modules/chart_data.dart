import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '/analytics/presentation/app_resources.dart';
import '/analytics/modules/chart_dialog.dart';
import '/analytics/modules/chart_titles.dart';
import '/analytics/modules/workout_utils.dart';

class ChartData {
  // Inside the ChartData class
  static LineChartData sampleData1(
    BuildContext context,
    List<int> activeIndices,
  ) => LineChartData(
    lineTouchData: _lineTouchData1(context, activeIndices),
    gridData: _gridData,
    titlesData: ChartTitles.titlesData1,
    borderData: _borderData,
    lineBarsData: _getFilteredLineBarsData(_lineBarsData1, activeIndices),
    minX: 0,
    maxX: 14,
    maxY: 100,
    minY: 0,
  );

  static LineChartData sampleData2(
    BuildContext context,
    List<int> activeIndices,
  ) => LineChartData(
    lineTouchData: _lineTouchData2,
    gridData: _gridData,
    titlesData: ChartTitles.titlesData2,
    borderData: _borderData,
    lineBarsData: _getFilteredLineBarsData(_lineBarsData2, activeIndices),
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

        // Now use actualWorkoutIndex to determine workout type
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
        final date = WorkoutUtils.getDateForXValue(spot.x);

        // Display the details dialog for the selected workout
        WorkoutDialog.showWorkoutDetailsDialog(
          context,
          workoutType,
          accuracy,
          date,
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

  static LineChartBarData _lineChartBarData(
    String title,
    Color color,
    List<FlSpot> spots,
  ) {
    return LineChartBarData(
      isCurved: true,
      color: color,
      barWidth: 3,
      isStrokeCapRound: true,
      dotData: FlDotData(
        show: true,
        getDotPainter:
            (spot, percent, barData, index) => FlDotCirclePainter(
              radius: 4,
              color: color,
              strokeWidth: 2,
              strokeColor: Colors.white,
            ),
      ),
      belowBarData: BarAreaData(show: false),
      spots: spots,
    );
  }

  static List<LineChartBarData> get _lineBarsData1 => [
    // Squat
    _lineChartBarData('Squat', AppColors.contentColorGreen, const [
      FlSpot(2, 25),
      FlSpot(4, 20),
      FlSpot(6, 37),
      FlSpot(8, 28),
      FlSpot(10, 45),
      FlSpot(12, 60),
      FlSpot(14, 70),
    ]),
    // Plank
    _lineChartBarData('Plank', AppColors.contentColorPink, const [
      FlSpot(1, 32),
      FlSpot(3, 46),
      FlSpot(5, 78),
      FlSpot(7, 55),
      FlSpot(9, 69),
      FlSpot(11, 83),
      FlSpot(13, 95),
    ]),
    // Push Up
    _lineChartBarData('Push Up', AppColors.contentColorCyan, const [
      FlSpot(2, 68),
      FlSpot(5, 54),
      FlSpot(8, 89),
      FlSpot(11, 80),
      FlSpot(14, 87),
    ]),
    // Shoulder Press
    _lineChartBarData('Shoulder Press', Colors.orange, const [
      FlSpot(1, 43),
      FlSpot(4, 54),
      FlSpot(7, 40),
      FlSpot(10, 67),
      FlSpot(13, 89),
    ]),
    // Bicep Curl
    _lineChartBarData('Bicep Curl', Colors.purple, const [
      FlSpot(2, 23),
      FlSpot(5, 46),
      FlSpot(8, 31),
      FlSpot(11, 55),
      FlSpot(14, 63),
    ]),
    // Lunges
    _lineChartBarData('Lunges', Colors.amber, const [
      FlSpot(3, 27),
      FlSpot(6, 43),
      FlSpot(9, 76),
      FlSpot(12, 61),
      FlSpot(14, 89),
    ]),
  ];

  static List<LineChartBarData> get _lineBarsData2 => _lineBarsData1;

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
