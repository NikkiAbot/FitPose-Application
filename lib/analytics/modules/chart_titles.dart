import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class ChartTitles {
  static FlTitlesData get titlesData1 => FlTitlesData(
    bottomTitles: AxisTitles(sideTitles: bottomTitles),
    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    leftTitles: AxisTitles(sideTitles: leftTitles()),
  );

  static FlTitlesData get titlesData2 => FlTitlesData(
    bottomTitles: AxisTitles(sideTitles: bottomTitles),
    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    leftTitles: AxisTitles(sideTitles: leftTitles()),
  );

  static Widget accuracyTitles(double value, TitleMeta meta) {
    final style = GoogleFonts.poppins(
      fontWeight: FontWeight.bold,
      fontSize: 12,
    );
    String text;
    switch (value.toInt()) {
      case 20:
        text = '20%';
        break;
      case 40:
        text = '40%';
        break;
      case 60:
        text = '60%';
        break;
      case 80:
        text = '80%';
        break;
      case 100:
        text = '100%';
        break;
      default:
        return Container();
    }

    return SideTitleWidget(
      meta: meta,
      child: Text(text, style: style, textAlign: TextAlign.center),
    );
  }

  static SideTitles leftTitles() => SideTitles(
    getTitlesWidget: accuracyTitles,
    showTitles: true,
    interval: 20,
    reservedSize: 40,
  );

  static Widget dates(double value, TitleMeta meta) {
    final style = GoogleFonts.poppins(
      fontWeight: FontWeight.bold,
      fontSize: 12,
    );
    Widget text;
    switch (value.toInt()) {
      case 2:
        text = Text('05/01', style: style);
        break;
      case 5:
        text = Text('05/10', style: style);
        break;
      case 8:
        text = Text('05/15', style: style);
        break;
      case 11:
        text = Text('05/20', style: style);
        break;
      case 14:
        text = Text('05/30', style: style);
        break;
      default:
        text = Text('', style: style);
        break;
    }

    return SideTitleWidget(meta: meta, space: 10, child: text);
  }

  static SideTitles get bottomTitles => SideTitles(
    showTitles: true,
    reservedSize: 32,
    interval: 1,
    getTitlesWidget: dates,
  );
}
