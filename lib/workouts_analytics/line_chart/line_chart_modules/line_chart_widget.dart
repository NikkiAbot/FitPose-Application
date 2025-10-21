import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'chart_data.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class LineChartWidget extends StatelessWidget {
  final bool isShowingMainData;
  final List<int> activeIndices;
  final DateTime? selectedDate; // optional
  final bool hideInternalLegend;
  final List<LineChartBarData>? externalBars; // provided by caller

  const LineChartWidget({
    super.key,
    required this.isShowingMainData,
    required this.activeIndices,
    this.selectedDate,
    this.hideInternalLegend = false,
    this.externalBars,
  });

  @override
  Widget build(BuildContext context) {
    // Pass externalBars (or empty list) to ChartData; ChartData no longer contains hard-coded series.
    final bars = externalBars ?? <LineChartBarData>[];

    return LineChart(
      isShowingMainData
          ? ChartData.sampleData1(context, activeIndices, bars)
          : ChartData.sampleData2(context, activeIndices, bars),
      duration: const Duration(milliseconds: 250),
    );
  }
}
