import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../main.dart';
import '../models/pace_summary.dart';
import '../providers/campaigns_provider.dart';
import '../widgets/app_sidebar.dart';

final _fmtRub = NumberFormat.currency(
  locale: 'ru_RU',
  symbol: '₽',
  decimalDigits: 0,
);
final _fmtDate = DateFormat('dd.MM.yyyy');
final _fmtDayMonth = DateFormat('dd.MM');
final _fmtHours = NumberFormat('#,##0.#', 'ru_RU');

Color _statusColor(PaceStatus status) {
  switch (status) {
    case PaceStatus.red:
      return Colors.red;
    case PaceStatus.yellow:
      return const Color(0xFFF9A825);
    case PaceStatus.green:
      return const Color(0xFF2E7D32);
  }
}

String _statusLabel(PaceStatus status) {
  switch (status) {
    case PaceStatus.red:
      return 'Отстаём';
    case PaceStatus.yellow:
      return 'Небольшое отставание';
    case PaceStatus.green:
      return 'В графике';
  }
}

class BudgetsPaceScreen extends ConsumerWidget {
  const BudgetsPaceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final campaignsState = ref.watch(campaignsProvider);
    final today = DateTime.now();

    return AppShell(
      section: AppSection.budgetsPace,
      child: Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Бюджеты и темпы',
          style: TextStyle(
            color: kTextPrimary,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Обновить',
            onPressed: () => ref.read(campaignsProvider.notifier).fetch(),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: campaignsState.when(
        loading: () =>
            const Center(child: CircularProgressIndicator(color: kAccent)),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Не удалось загрузить кампании.\n$e',
              textAlign: TextAlign.center,
              style: const TextStyle(color: kTextSecondary),
            ),
          ),
        ),
        data: (campaigns) {
          final summaries =
              campaigns
                  .where((c) => c.isActive && (c.budget ?? 0) > 0)
                  .map((c) {
                    // Поле spent из списка кампаний часто пустое/нулевое —
                    // как и на карточке кампании, в этом случае берём
                    // фактический бюджет из impression-stats.
                    final cardStats = (c.spent == null || c.spent! <= 0)
                        ? ref
                              .watch(campaignStatsProvider(c.id))
                              .whenOrNull(data: (s) => s)
                        : null;
                    final spentOverride = (c.spent != null && c.spent! > 0)
                        ? c.spent!
                        : (cardStats?.factBudget ?? 0.0);
                    // timeSettings нет в списочном ответе — догружаем из
                    // детального, иначе лимиты считаются от круглых суток.
                    final schedule = ref
                        .watch(campaignScheduleProvider(c.id))
                        .whenOrNull(data: (value) => value);
                    return CampaignPaceSummary.fromCampaign(
                      c,
                      today,
                      spentOverride: spentOverride,
                      schedule: schedule,
                    );
                  })
                  .where((s) => s.totalDays > 0)
                  .toList()
                ..sort((a, b) => a.pacePct.compareTo(b.pacePct));

          if (summaries.isEmpty) {
            return const Center(
              child: Text(
                'Нет активных кампаний с заданным бюджетом и датами.',
                style: TextStyle(color: kTextSecondary),
              ),
            );
          }

          final totalBudget = summaries.fold(0.0, (s, c) => s + c.budget);
          final totalSpent = summaries.fold(0.0, (s, c) => s + c.spent);
          final totalPlanToDate = summaries.fold(
            0.0,
            (s, c) => s + c.planToDate,
          );
          final totalRemaining = summaries.fold(
            0.0,
            (s, c) => s + c.remainingBudget,
          );
          final totalPlanToNow = summaries.fold(0.0, (s, c) => s + c.planToNow);
          final totalShortfall = totalPlanToNow - totalSpent;

          return Padding(
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowHeight: 40,
                  dataRowMinHeight: 44,
                  dataRowMaxHeight: 56,
                  columns: const [
                    DataColumn(label: Text('Кампания')),
                    DataColumn(label: Text('Период')),
                    DataColumn(label: Text('Бюджет'), numeric: true),
                    DataColumn(label: Text('Факт'), numeric: true),
                    DataColumn(label: Text('% освоено'), numeric: true),
                    DataColumn(label: Text('Сейчас: факт / план'), numeric: true),
                    DataColumn(label: Text('Не хватает'), numeric: true),
                    DataColumn(label: Text('Темп'), numeric: true),
                    DataColumn(label: Text('Остаток'), numeric: true),
                    DataColumn(label: Text('Ост. дней'), numeric: true),
                    DataColumn(label: Text('Лимит/сутки'), numeric: true),
                    DataColumn(label: Text('Лимит/час'), numeric: true),
                  ],
                  rows: [
                    ...summaries.map((s) => _paceRow(s)),
                    DataRow(
                      color: WidgetStateProperty.all(kAccentLight),
                      cells: [
                        const DataCell(
                          Text('ИТОГО', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                        const DataCell(Text('')),
                        DataCell(Text(_fmtRub.format(totalBudget))),
                        DataCell(Text(_fmtRub.format(totalSpent))),
                        DataCell(
                          Text(
                            totalBudget == 0
                                ? '—'
                                : '${(totalSpent / totalBudget * 100).toStringAsFixed(1)}%',
                          ),
                        ),
                        DataCell(
                          Text(
                            '${_fmtRub.format(totalSpent)} / '
                            '${_fmtRub.format(totalPlanToNow)}',
                          ),
                        ),
                        DataCell(
                          Text(
                            totalShortfall.abs() < 1
                                ? '—'
                                : '${totalShortfall > 0 ? '' : '+'}'
                                      '${_fmtRub.format(totalShortfall.abs())}',
                            style: TextStyle(
                              color: totalShortfall > 0
                                  ? Colors.red
                                  : const Color(0xFF2E7D32),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        DataCell(
                          Text(
                            totalPlanToDate == 0
                                ? '—'
                                : '${(totalSpent / totalPlanToDate * 100).toStringAsFixed(1)}%',
                          ),
                        ),
                        DataCell(Text(_fmtRub.format(totalRemaining))),
                        const DataCell(Text('')),
                        const DataCell(Text('')),
                        const DataCell(Text('')),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
      ),
    );
  }

  DataRow _paceRow(CampaignPaceSummary s) {
    final color = _statusColor(s.status);
    return DataRow(
      cells: [
        DataCell(
          SizedBox(
            width: 220,
            child: Text(s.name, overflow: TextOverflow.ellipsis, maxLines: 2),
          ),
        ),
        DataCell(_periodChip(s)),
        DataCell(Text(_fmtRub.format(s.budget))),
        DataCell(Text(_fmtRub.format(s.spent))),
        DataCell(Text('${(s.pctSpent * 100).toStringAsFixed(1)}%')),
        DataCell(
          Tooltip(
            message:
                'План на текущий момент — по доле уже прошедшего эфирного '
                'времени, а не по целым дням',
            child: Text(
              '${_fmtRub.format(s.spent)} / ${_fmtRub.format(s.planToNow)}',
            ),
          ),
        ),
        DataCell(_shortfallText(s)),
        DataCell(
          Tooltip(
            message: _statusLabel(s.status),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${(s.pacePct * 100).toStringAsFixed(1)}%',
                style: TextStyle(color: color, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ),
        DataCell(Text(_fmtRub.format(s.remainingBudget))),
        DataCell(
          Tooltip(
            message: s.scheduleResolved && s.hasTimeRestrictions
                ? '${s.daysLeft} календарных, из них ${s.broadcastDaysLeft} '
                      'с вещанием'
                : '${s.daysLeft} календарных дн. до конца кампании',
            child: Text('${s.daysLeft}'),
          ),
        ),
        DataCell(
          Tooltip(
            message: _limitHint(
              s,
              'Остаток ÷ ${s.broadcastDaysLeft} дн. вещания',
              'Остаток ÷ ${s.broadcastDaysLeft} дн. (кампания идёт круглосуточно)',
              'Остаток ÷ ${s.daysLeft} календарных дн.',
            ),
            child: _limitText(_fmtRub.format(s.dailyLimit), s.scheduleResolved),
          ),
        ),
        DataCell(
          Tooltip(
            message: _limitHint(
              s,
              'Остаток ÷ ${_fmtHours.format(s.broadcastHoursLeft)} ч вещания '
                  'по расписанию, оставшихся до конца кампании',
              'Остаток ÷ ${_fmtHours.format(s.broadcastHoursLeft)} ч, оставшихся '
                  'до конца кампании: ограничений по времени нет, кампания идёт '
                  'круглосуточно',
              'Расписание не загрузилось — считаем круглые сутки '
                  '(${_fmtHours.format(s.broadcastHoursLeft)} ч)',
            ),
            child: _limitText(_fmtRub.format(s.hourlyLimit), s.scheduleResolved),
          ),
        ),
      ],
    );
  }

  /// Даты кампании одной компактной плашкой: две отдельные колонки съедали
  /// заметно больше ширины, чем несут смысла.
  Widget _periodChip(CampaignPaceSummary s) {
    final start = s.startDate;
    final end = s.endDate;
    if (start == null && end == null) return const Text('—');

    final sameYear = start != null && end != null && start.year == end.year;
    final left = start == null
        ? '—'
        : (sameYear ? _fmtDayMonth : _fmtDate).format(start);
    final right = end == null ? '—' : _fmtDate.format(end);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: kBg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: kBorder),
      ),
      child: Text(
        '$left – $right',
        style: const TextStyle(fontSize: 12, color: kTextSecondary),
      ),
    );
  }

  /// Недобор до плана на текущий момент. Перелив показываем со знаком плюс и
  /// зелёным — это не ошибка, а обгон плана.
  Widget _shortfallText(CampaignPaceSummary s) {
    final diff = s.shortfallNow;
    if (diff.abs() < 1) return const Text('—');
    final behind = diff > 0;
    return Text(
      '${behind ? '' : '+'}${_fmtRub.format(behind ? diff : -diff)}',
      style: TextStyle(
        color: behind ? Colors.red : const Color(0xFF2E7D32),
        fontWeight: FontWeight.w600,
      ),
    );
  }

  /// Три разных случая, которые раньше сваливались в один: есть расписание,
  /// расписания нет по факту (круглосуточно — это достоверный расчёт), и
  /// расписание не удалось загрузить (вот тут цифре верить нельзя).
  String _limitHint(
    CampaignPaceSummary s,
    String restricted,
    String roundTheClock,
    String unresolved,
  ) {
    if (!s.scheduleResolved) return unresolved;
    return s.hasTimeRestrictions ? restricted : roundTheClock;
  }

  /// Звёздочка — только когда расписание не загрузилось. Кампания без
  /// ограничений по времени считается корректно, помечать её незачем.
  Widget _limitText(String value, bool scheduleResolved) {
    if (scheduleResolved) return Text(value);
    return Text('$value*', style: const TextStyle(color: kTextSecondary));
  }
}
