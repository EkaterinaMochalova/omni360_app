import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../main.dart';
import '../models/pace_summary.dart';
import '../providers/campaigns_provider.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/loading_placeholders.dart';

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
          final rows = campaigns
              .where((c) => c.isActive && (c.budget ?? 0) > 0)
              .toList();

          final summaries =
              rows
                  .map((c) {
                    // Статистику берём всегда: из неё и фактический бюджет
                    // (поле spent в списке часто пустое), и установленный
                    // часовой лимит — с ним сравниваем рекомендуемый.
                    final cardStats = ref
                        .watch(campaignStatsProvider(c.id))
                        .whenOrNull(data: (s) => s);
                    final spentOverride = (c.spent != null && c.spent! > 0)
                        ? c.spent!
                        : (cardStats?.factBudget ?? 0.0);
                    // Расписание грузится по строке и приходит независимо от
                    // соседей — одновременных запросов не больше трёх,
                    // ограничитель стоит в самом провайдере.
                    final scheduleAsync = ref.watch(
                      campaignScheduleProvider(c.id),
                    );
                    return CampaignPaceSummary.fromCampaign(
                      c,
                      today,
                      spentOverride: spentOverride,
                      schedule: scheduleAsync.valueOrNull,
                      scheduleLoading: scheduleAsync.isLoading,
                      currentHourlyLimit: cardStats?.hourlyBudgetPlan,
                    );
                  })
                  .where((s) => s.totalDays > 0)
                  .toList()
                ..sort((a, b) => a.pacePctNow.compareTo(b.pacePctNow));

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
                    DataColumn(
                      label: Text('Рекоменд. лимит/сутки'),
                      numeric: true,
                    ),
                    DataColumn(
                      label: Text('Рекоменд. лимит/час'),
                      numeric: true,
                    ),
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
                            totalPlanToNow == 0
                                ? '—'
                                : '${(totalSpent / totalPlanToNow * 100).toStringAsFixed(1)}%',
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
                '${(s.pacePctNow * 100).toStringAsFixed(1)}%',
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
            child: _limitCell(
              s,
              s.dailyLimit,
              s.currentDailyLimit,
              s.dailyLimitFactor,
            ),
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
            child: _limitCell(
              s,
              s.hourlyLimit,
              s.currentHourlyLimit,
              s.hourlyLimitFactor,
            ),
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

  /// Рекомендуемый лимит и, если установленный лимит известен, — насколько
  /// его надо менять. Без этого сравнения непонятно, поднимать или снижать.
  Widget _limitCell(
    CampaignPaceSummary s,
    double recommended,
    double? current,
    double? factor,
  ) {
    final value = _limitText(s, _fmtRub.format(recommended));
    if (factor == null || current == null) return value;

    // Разница в пределах 5% — шум, гонять лимит из-за неё незачем.
    final aligned = (factor - 1).abs() < 0.05;
    final raise = factor > 1;
    final color = aligned
        ? kTextSecondary
        : (raise ? const Color(0xFFF9A825) : const Color(0xFF2E7D32));
    final label = aligned
        ? 'как сейчас'
        : '${raise ? '↑' : '↓'} ${(factor * 100).toStringAsFixed(0)}% '
              'от ${_fmtRub.format(current)}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        value,
        Text(label, style: TextStyle(color: color, fontSize: 11)),
      ],
    );
  }

  /// Звёздочка — только когда расписание не загрузилось. Кампания без
  /// ограничений по времени считается корректно, помечать её незачем, а пока
  /// расписание ещё едет — это многоточие, а не признак недостоверности.
  Widget _limitText(CampaignPaceSummary s, String value) {
    if (s.scheduleResolved) return Text(value);
    if (s.scheduleLoading) {
      // Живое многоточие вместо статичного: видно, что расписание ещё едет.
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value, style: const TextStyle(color: kTextSecondary)),
          const LoadingDots(),
        ],
      );
    }
    return Text('$value*', style: const TextStyle(color: kTextSecondary));
  }
}
