import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../main.dart';
import '../models/pace_summary.dart';
import '../providers/campaigns_provider.dart';

final _fmtRub = NumberFormat.currency(
  locale: 'ru_RU',
  symbol: '₽',
  decimalDigits: 0,
);
final _fmtDate = DateFormat('dd.MM.yyyy');

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

    return Scaffold(
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
                  .map((c) => CampaignPaceSummary.fromCampaign(c, today))
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
                    DataColumn(label: Text('Начало')),
                    DataColumn(label: Text('Конец')),
                    DataColumn(label: Text('Бюджет'), numeric: true),
                    DataColumn(label: Text('Факт'), numeric: true),
                    DataColumn(label: Text('% освоено'), numeric: true),
                    DataColumn(label: Text('План к сегодня'), numeric: true),
                    DataColumn(label: Text('Темп'), numeric: true),
                    DataColumn(label: Text('Остаток'), numeric: true),
                    DataColumn(label: Text('Дней осталось'), numeric: true),
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
                        DataCell(Text(_fmtRub.format(totalPlanToDate))),
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
        DataCell(Text(s.startDate != null ? _fmtDate.format(s.startDate!) : '—')),
        DataCell(Text(s.endDate != null ? _fmtDate.format(s.endDate!) : '—')),
        DataCell(Text(_fmtRub.format(s.budget))),
        DataCell(Text(_fmtRub.format(s.spent))),
        DataCell(Text('${(s.pctSpent * 100).toStringAsFixed(1)}%')),
        DataCell(Text(_fmtRub.format(s.planToDate))),
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
        DataCell(Text('${s.daysLeft}')),
        DataCell(Text(_fmtRub.format(s.dailyLimit))),
        DataCell(Text(_fmtRub.format(s.hourlyLimit))),
      ],
    );
  }
}
