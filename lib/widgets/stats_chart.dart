import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../models/campaign.dart';

class StatsChart extends StatelessWidget {
  final List<DailyStat> daily;

  const StatsChart({super.key, required this.daily});

  @override
  Widget build(BuildContext context) {
    if (daily.isEmpty) return const SizedBox.shrink();

    final maxY = daily
            .map((e) => e.impressions.toDouble())
            .reduce((a, b) => a > b ? a : b) *
        1.2;

    return LineChart(
      LineChartData(
        minY: 0,
        maxY: maxY,
        gridData: FlGridData(
          drawHorizontalLine: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) => const FlLine(
            color: Colors.white10,
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              interval: (daily.length / 5).ceilToDouble().clamp(1, double.infinity),
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= daily.length) return const SizedBox.shrink();
                final date = daily[i].date;
                final parts = date.split('-');
                final label = parts.length >= 2 ? '${parts[2]}.${parts[1]}' : date;
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(label,
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 10)),
                );
              },
            ),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: daily
                .asMap()
                .entries
                .map((e) =>
                    FlSpot(e.key.toDouble(), e.value.impressions.toDouble()))
                .toList(),
            isCurved: true,
            color: const Color(0xFF6C63FF),
            barWidth: 2.5,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: const Color(0xFF6C63FF).withValues(alpha: 0.1),
            ),
          ),
        ],
      ),
    );
  }
}
