import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../main.dart';

final _fmtInt = NumberFormat.decimalPattern('ru_RU');

/// Доля кольцевой диаграммы. Может раскрываться на составляющие.
class DonutSlice {
  final String label;
  final int value;
  final Color color;

  /// Из чего состоит доля. Пустой список — раскрывать нечего.
  ///
  /// Причины отклонений — это части отклонённых показов, а не категории
  /// наравне с ними: рядом на одном кольце они давали сумму больше 100% и
  /// сбивали с толку. Поэтому они лежат здесь, внутри своей доли.
  final List<DonutSlice> children;

  const DonutSlice({
    required this.label,
    required this.value,
    required this.color,
    this.children = const [],
  });

  bool get expandable => children.any((c) => c.value > 0);
}

/// Кольцевая диаграмма с легендой сбоку и раскрытием доли по клику.
///
/// Наведение показывает цифры доли в центре кольца, наведение на пункт легенды
/// подсвечивает соответствующую долю. Клик по доле с составом раскрывает её.
class DonutBreakdown extends StatefulWidget {
  final List<DonutSlice> slices;

  const DonutBreakdown({super.key, required this.slices});

  @override
  State<DonutBreakdown> createState() => _DonutBreakdownState();
}

class _DonutBreakdownState extends State<DonutBreakdown> {
  /// Подсвеченная доля — наведением по диаграмме или по легенде.
  int? _active;

  /// Метка раскрытой доли. Держим метку, а не индекс: список пересобирается
  /// на каждой перерисовке, и индекс после обновления данных мог указать
  /// на чужую долю.
  String? _expanded;

  /// Плоский список того, что реально нарисовано: раскрытая доля заменена
  /// своими составляющими.
  List<_Entry> _visible() {
    final result = <_Entry>[];
    for (final slice in widget.slices) {
      if (slice.value <= 0) continue;
      final isExpanded = _expanded == slice.label && slice.expandable;
      if (!isExpanded) {
        result.add(_Entry(slice: slice, parentLabel: null));
        continue;
      }
      for (final child in slice.children) {
        if (child.value <= 0) continue;
        result.add(_Entry(slice: child, parentLabel: slice.label));
      }
    }
    return result;
  }

  void _toggle(String label) {
    setState(() {
      // Клик по составляющей — сворачиваем родителя обратно.
      final parent = _visible()
          .firstWhere(
            (e) => e.slice.label == label,
            orElse: () => _Entry(
              slice: const DonutSlice(
                label: '',
                value: 0,
                color: Colors.transparent,
              ),
              parentLabel: null,
            ),
          )
          .parentLabel;
      if (parent != null) {
        _expanded = null;
        _active = null;
        return;
      }
      final slice = widget.slices.firstWhere(
        (s) => s.label == label,
        orElse: () => const DonutSlice(
          label: '',
          value: 0,
          color: Colors.transparent,
        ),
      );
      if (!slice.expandable) return;
      _expanded = _expanded == label ? null : label;
      _active = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final entries = _visible();
    if (entries.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Text(
          'Нет данных за выбранный период.',
          style: TextStyle(color: kTextSecondary, fontSize: 12),
        ),
      );
    }

    // Знаменатель — всегда сумма верхнего уровня, чтобы при раскрытии
    // проценты не пересчитывались от отклонённых и оставались сопоставимыми.
    final total = widget.slices
        .where((s) => s.value > 0)
        .fold<int>(0, (sum, s) => sum + s.value);

    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 420;
        final chart = SizedBox(
          height: 190,
          width: 190,
          child: Stack(
            alignment: Alignment.center,
            children: [
              _chart(entries, total),
              IgnorePointer(child: _center(entries, total)),
            ],
          ),
        );
        final legend = _legend(entries, total);

        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [Center(child: chart), const SizedBox(height: 12), legend],
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

  Widget _chart(List<_Entry> entries, int total) {
    return PieChart(
      PieChartData(
        sectionsSpace: 2,
        centerSpaceRadius: 52,
        startDegreeOffset: -90,
        pieTouchData: PieTouchData(
          enabled: true,
          touchCallback: (event, response) {
            final index = response?.touchedSection?.touchedSectionIndex;
            final valid = index != null && index >= 0 && index < entries.length;
            if (event is FlTapUpEvent && valid) {
              _toggle(entries[index].slice.label);
              return;
            }
            // Событие выхода курсора приходит с index == -1.
            final next = valid ? index : null;
            if (next != _active) setState(() => _active = next);
          },
        ),
        sections: [
          for (var i = 0; i < entries.length; i++)
            PieChartSectionData(
              value: entries[i].slice.value.toDouble(),
              color: i == _active
                  ? entries[i].slice.color
                  : entries[i].slice.color.withValues(alpha: 0.85),
              radius: i == _active ? 46 : 38,
              showTitle: false,
            ),
        ],
      ),
      swapAnimationDuration: const Duration(milliseconds: 150),
    );
  }

  /// Центр кольца: цифры наведённой доли, иначе — итог и подсказка про клик.
  Widget _center(List<_Entry> entries, int total) {
    final index = _active;
    final entry = (index != null && index >= 0 && index < entries.length)
        ? entries[index]
        : null;

    // Внутри кольца помещается только две короткие строки: подсказка про клик
    // раньше лезла на сектора и обрезалась, поэтому она ушла под легенду.
    if (entry == null) {
      return SizedBox(
        width: 84,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _fmtInt.format(total),
              maxLines: 1,
              style: const TextStyle(
                color: kTextPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Text(
              'запросов',
              style: TextStyle(color: kTextSecondary, fontSize: 11),
            ),
          ],
        ),
      );
    }

    final percent = total == 0 ? 0.0 : entry.slice.value / total * 100;
    return SizedBox(
      width: 84,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            entry.slice.label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: entry.slice.color,
              fontSize: 9,
              height: 1.15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            _fmtInt.format(entry.slice.value),
            maxLines: 1,
            style: const TextStyle(
              color: kTextPrimary,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            '${percent.toStringAsFixed(1)}%',
            style: const TextStyle(color: kTextSecondary, fontSize: 10),
          ),
        ],
      ),
    );
  }

  Widget _legend(List<_Entry> entries, int total) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < entries.length; i++)
          _LegendRow(
            slice: entries[i].slice,
            percent: total == 0 ? 0 : entries[i].slice.value / total * 100,
            active: i == _active,
            expandable: entries[i].slice.expandable,
            nested: entries[i].parentLabel != null,
            onHover: (hovering) {
              final next = hovering ? i : null;
              if (hovering || _active == i) setState(() => _active = next);
            },
            onTap: () => _toggle(entries[i].slice.label),
          ),
        if (widget.slices.any((s) => s.expandable))
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 6),
            child: Text(
              _expanded == null
                  ? 'Клик по отклонённым — разбить на причины'
                  : 'Показаны причины отклонений. Клик — вернуться',
              style: const TextStyle(color: kTextSecondary, fontSize: 10),
            ),
          ),
      ],
    );
  }
}

/// Нарисованная доля вместе со ссылкой на родителя, если это составляющая.
class _Entry {
  final DonutSlice slice;
  final String? parentLabel;

  const _Entry({required this.slice, required this.parentLabel});
}

class _LegendRow extends StatelessWidget {
  final DonutSlice slice;
  final double percent;
  final bool active;
  final bool expandable;
  final bool nested;
  final ValueChanged<bool> onHover;
  final VoidCallback onTap;

  const _LegendRow({
    required this.slice,
    required this.percent,
    required this.active,
    required this.expandable,
    required this.nested,
    required this.onHover,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => onHover(true),
      onExit: (_) => onHover(false),
      cursor: (expandable || nested)
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: (expandable || nested) ? onTap : null,
        child: Container(
          padding: EdgeInsets.only(
            left: nested ? 18 : 6,
            right: 6,
            top: 3,
            bottom: 3,
          ),
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
              if (expandable)
                const Padding(
                  padding: EdgeInsets.only(right: 4),
                  child: Icon(
                    Icons.unfold_more_rounded,
                    size: 13,
                    color: kTextSecondary,
                  ),
                ),
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
      ),
    );
  }
}
