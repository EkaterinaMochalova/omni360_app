import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../main.dart';

final _fmtInt = NumberFormat.decimalPattern('ru_RU');

/// Одна доля кольцевой диаграммы.
class DonutSlice {
  final String label;
  final int value;
  final Color color;

  /// Группа, к которой относится доля («Статусы», «Причины проигрышей») —
  /// показывается в легенде, чтобы объединённая диаграмма не путала.
  final String group;

  const DonutSlice({
    required this.label,
    required this.value,
    required this.color,
    required this.group,
  });
}

/// Кольцевая диаграмма с легендой сбоку.
///
/// Наведение на долю показывает всплывающую подсказку с числом и процентом,
/// наведение на пункт легенды подсвечивает соответствующую долю — связь в обе
/// стороны, иначе на диаграмме с десятком долей не понять, что где.
class DonutBreakdown extends StatefulWidget {
  final List<DonutSlice> slices;

  const DonutBreakdown({super.key, required this.slices});

  @override
  State<DonutBreakdown> createState() => _DonutBreakdownState();
}

class _DonutBreakdownState extends State<DonutBreakdown> {
  /// Индекс подсвеченной доли: наведением по диаграмме или по легенде.
  int? _active;

  @override
  Widget build(BuildContext context) {
    final slices = widget.slices.where((s) => s.value > 0).toList();
    if (slices.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Text(
          'Нет данных за выбранный период.',
          style: TextStyle(color: kTextSecondary, fontSize: 12),
        ),
      );
    }

    final total = slices.fold<int>(0, (sum, s) => sum + s.value);

    return LayoutBuilder(
      builder: (context, constraints) {
        // На узкой карточке легенда уходит под диаграмму, иначе и то и другое
        // сжимается до нечитаемого.
        final stacked = constraints.maxWidth < 420;
        final chart = SizedBox(
          height: 190,
          width: 190,
          child: _chart(slices, total),
        );
        final legend = _legend(slices, total);

        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: chart),
              const SizedBox(height: 12),
              legend,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            chart,
            const SizedBox(width: 20),
            Expanded(child: legend),
          ],
        );
      },
    );
  }

  Widget _chart(List<DonutSlice> slices, int total) {
    return PieChart(
      PieChartData(
        sectionsSpace: 2,
        centerSpaceRadius: 52,
        startDegreeOffset: -90,
        pieTouchData: PieTouchData(
          enabled: true,
          touchCallback: (event, response) {
            final index = response?.touchedSection?.touchedSectionIndex;
            // Событие выхода курсора приходит с index == -1.
            final next = (index == null || index < 0) ? null : index;
            if (next != _active) setState(() => _active = next);
          },
        ),
        sections: [
          for (var i = 0; i < slices.length; i++)
            _section(slices[i], i, total, i == _active),
        ],
      ),
      // Без явной длительности перерисовка на каждом движении курсора
      // выглядит как дрожание.
      duration: const Duration(milliseconds: 120),
    );
  }

  PieChartSectionData _section(
    DonutSlice slice,
    int index,
    int total,
    bool active,
  ) {
    final percent = total == 0 ? 0.0 : slice.value / total * 100;
    return PieChartSectionData(
      value: slice.value.toDouble(),
      color: active ? slice.color : slice.color.withValues(alpha: 0.85),
      radius: active ? 46 : 38,
      showTitle: false,
      // Всплывающая карточка с цифрами — вместо подписи прямо на доле, которая
      // на мелких сегментах всё равно не читается.
      badgeWidget: active
          ? _Tooltip(
              label: slice.label,
              value: slice.value,
              percent: percent,
            )
          : null,
      badgePositionPercentageOffset: 1.45,
    );
  }

  Widget _legend(List<DonutSlice> slices, int total) {
    final groups = <String, List<int>>{};
    for (var i = 0; i < slices.length; i++) {
      groups.putIfAbsent(slices[i].group, () => []).add(i);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final entry in groups.entries) ...[
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 2),
            child: Text(
              entry.key,
              style: const TextStyle(
                color: kTextSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          for (final index in entry.value)
            _LegendRow(
              slice: slices[index],
              percent: total == 0 ? 0 : slices[index].value / total * 100,
              active: index == _active,
              onHover: (hovering) {
                final next = hovering ? index : null;
                if (hovering || _active == index) {
                  setState(() => _active = next);
                }
              },
            ),
        ],
      ],
    );
  }
}

class _LegendRow extends StatelessWidget {
  final DonutSlice slice;
  final double percent;
  final bool active;
  final ValueChanged<bool> onHover;

  const _LegendRow({
    required this.slice,
    required this.percent,
    required this.active,
    required this.onHover,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => onHover(true),
      onExit: (_) => onHover(false),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: active ? kAccentLight : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: slice.color,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                slice.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: kTextPrimary,
                  fontSize: 12,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _fmtInt.format(slice.value),
              style: const TextStyle(
                color: kTextPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 6),
            SizedBox(
              width: 46,
              child: Text(
                '${percent.toStringAsFixed(1)}%',
                textAlign: TextAlign.right,
                style: const TextStyle(color: kTextSecondary, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tooltip extends StatelessWidget {
  final String label;
  final int value;
  final double percent;

  const _Tooltip({
    required this.label,
    required this.value,
    required this.percent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      constraints: const BoxConstraints(maxWidth: 190),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: kBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: kTextPrimary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            '${_fmtInt.format(value)} · ${percent.toStringAsFixed(1)}%',
            style: const TextStyle(color: kTextSecondary, fontSize: 11),
          ),
        ],
      ),
    );
  }
}
