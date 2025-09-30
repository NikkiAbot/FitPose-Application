import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '/analytics/modules/chart_data.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class LineChartWidget extends StatelessWidget {
  final bool isShowingMainData;
  final List<int> activeIndices;

  const LineChartWidget({
    super.key,
    required this.isShowingMainData,
    required this.activeIndices,
  });

  @override
  Widget build(BuildContext context) {
    return LineChart(
      isShowingMainData
          ? ChartData.sampleData1(context, activeIndices)
          : ChartData.sampleData2(context, activeIndices),
      duration: const Duration(milliseconds: 250),
    );
  }
}
