import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../main.dart';
import '../models/campaign.dart';
import '../models/campaign_analytics.dart';
import '../models/loss_report.dart';
import '../models/pace_summary.dart';
import '../providers/campaigns_provider.dart';
import 'card_section.dart';

final _fmtRub0 = NumberFormat.currency(
  locale: 'ru_RU',
  symbol: '₽',
  decimalDigits: 0,
);
final _fmtRub2 = NumberFormat.currency(
  locale: 'ru_RU',
  symbol: '₽',
  decimalDigits: 2,
);
final _fmtNum = NumberFormat.decimalPattern('ru_RU');
final _fmtDate = DateFormat('dd.MM.yyyy');

/// Экран без фотоотчёта, уже подписанный GID и оператором.
typedef _PhotoTarget = ({String label, String address, int shows});

/// Текстовая справка по кампании с рекомендациями — чтобы скопировать и
/// отправить клиенту.
///
/// Все цифры здесь уже есть в других блоках, но там они разложены по плашкам и
/// диаграммам: перенести это в письмо можно только вручную. Здесь то же самое
/// связным текстом, а списки поверхностей — рядом, в свёрнутом виде.
class CampaignRecommendationsCard extends StatelessWidget {
  final Campaign campaign;
  final CampaignStats? stats;
  final CampaignPhotoCoverage? coverage;

  /// Подписи поверхностей: GID и оператор по `inventory.id`.
  final Map<int, SurfaceLabel> surfaceLabels;

  final LossReport lossReport;

  /// Сколько всего попыток выхода было за период. От этого зависит, попадут ли
  /// ошибки операторов в письмо: единичные сбои клиенту не интересны.
  final int totalRequests;

  /// Период, за который посчитаны отклонения показов. Бюджет и темп считаются
  /// за всю кампанию, а отчёты по ставкам и операторам — только за него, и в
  /// письме клиенту это стоит различать.
  final DateTime periodStart;
  final DateTime periodEnd;

  /// Полная выгрузка показов ещё идёт — значит списки могут пополниться.
  final bool recordsLoading;

  const CampaignRecommendationsCard({
    super.key,
    required this.campaign,
    required this.stats,
    required this.coverage,
    required this.lossReport,
    required this.periodStart,
    required this.periodEnd,
    this.totalRequests = 0,
    this.surfaceLabels = const {},
    this.recordsLoading = false,
  });

  /// Доля, начиная с которой ошибки операторов попадают в письмо.
  ///
  /// Ниже неё это фоновый шум РТБ: клиенту он ничего не говорит, а раздел
  /// занимает половину письма.
  static const double operatorErrorShareThreshold = 0.2;

  CampaignPaceSummary get _pace {
    final spent = (campaign.spent != null && campaign.spent! > 0)
        ? campaign.spent!
        : (stats?.factBudget ?? 0);
    return CampaignPaceSummary.fromCampaign(
      campaign,
      DateTime.now(),
      spentOverride: spent,
      budgetOverride: stats?.planBudget,
      currentDailyLimit: stats?.planDailyBudget,
      currentHourlyLimit: stats?.hourlyBudgetPlan,
    );
  }

  /// Экраны без фотоотчёта, сгруппированные по оператору.
  Map<String, List<_PhotoTarget>> get _photoTargets {
    final grouped = <String, List<_PhotoTarget>>{};
    for (final side in coverage?.missing ?? const <PhotoMissingSide>[]) {
      final label = side.inventoryId == null
          ? null
          : surfaceLabels[side.inventoryId];
      final operatorName = (label?.operatorName ?? '').isNotEmpty
          ? label!.operatorName
          : 'Оператор не определён';
      final gid = (label?.gid ?? '').isNotEmpty ? label!.gid : side.name;
      grouped.putIfAbsent(operatorName, () => []).add((
        label: gid,
        address: label?.address ?? '',
        shows: side.shows,
      ));
    }
    return grouped;
  }

  /// Ошибки операторов — только количество по каждому оператору.
  ///
  /// Раньше здесь был весь отчёт «К оператору» с поверхностями и формулировками
  /// ошибок: клиенту он не нужен (это работа с оператором, а не его решение), а
  /// в письме занимал больше места, чем всё остальное вместе.
  ///
  /// Пустая карта, если таких ошибок меньше
  /// [operatorErrorShareThreshold] от всех попыток выхода.
  Map<String, int> get _operatorErrors {
    final total = lossReport.operatorIssueGroups.fold<int>(
      0,
      (sum, group) => sum + group.count,
    );
    if (total <= 0 ||
        totalRequests <= 0 ||
        total / totalRequests <= operatorErrorShareThreshold) {
      return const {};
    }

    final grouped = <String, int>{};
    for (final group in lossReport.operatorIssueGroups) {
      final name = group.operatorName.isEmpty
          ? 'Оператор не определён'
          : group.operatorName;
      grouped[name] = (grouped[name] ?? 0) + group.count;
    }
    return grouped;
  }

  /// Строка о периоде — та же, что в подзаголовке блока. В письме она нужна не
  /// меньше: без неё непонятно, за что цифры.
  String get _periodLine =>
      'Статистика по показам: ${_fmtDate.format(periodStart)} – '
      '${_fmtDate.format(periodEnd)}. Бюджет и темп — за весь срок кампании.';

  @override
  Widget build(BuildContext context) {
    final pace = _pace;
    final bids = lossReport.bidRaiseRows;
    final issues = _operatorErrors;
    final photos = _photoTargets;

    return CardSection(
      title: 'Рекомендации для клиента',
      subtitle: _periodLine,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (recordsLoading)
                const Expanded(
                  child: Text(
                    'Выгрузка показов ещё идёт — списки могут пополниться.',
                    style: TextStyle(color: Color(0xFFE65100), fontSize: 11),
                  ),
                )
              else
                const Spacer(),
              TextButton.icon(
                onPressed: () async {
                  await Clipboard.setData(
                    ClipboardData(text: _buildText(pace, bids, issues, photos)),
                  );
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Текст скопирован')),
                  );
                },
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 32),
                  foregroundColor: kAccent,
                ),
                icon: const Icon(Icons.copy_rounded, size: 16),
                label: const Text(
                  'Скопировать текст',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          _block('Как идёт кампания', _statusLines(pace)),
          const SizedBox(height: 12),
          _block('Что предлагаем', _adviceLines(pace, bids, issues, photos)),
          // Списки и таблицы — рядом с текстом, свёрнутые: в самом письме они
          // нужны целиком, а на экране занимали бы весь блок.
          if (issues.isNotEmpty) ...[
            const SizedBox(height: 12),
            _block('Ошибки на стороне оператора', _operatorErrorLines(issues)),
          ],
          if (bids.isNotEmpty) ...[
            const SizedBox(height: 8),
            _BidTile(rows: bids),
          ],
          if (photos.isNotEmpty) ...[
            const SizedBox(height: 4),
            _PhotosTile(targets: photos),
          ],
        ],
      ),
    );
  }

  Widget _block(String title, List<String> lines) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: kTextPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        for (final line in lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              line,
              style: const TextStyle(
                color: kTextPrimary,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
      ],
    );
  }

  // ── Тексты ─────────────────────────────────────────────────────────────────

  List<String> _statusLines(CampaignPaceSummary pace) {
    final lines = <String>[
      '${campaign.name} (ID ${campaign.id}) — ${campaign.displayStatus}.',
    ];

    if (campaign.startDate != null || campaign.endDate != null) {
      final left = pace.daysLeft > 0
          ? ', осталось ${pace.daysLeft} дн.'
          : ', срок закончился';
      lines.add(
        'Период: ${campaign.startDate ?? '—'} – ${campaign.endDate ?? '—'}'
        '$left',
      );
    }

    if (pace.budget > 0) {
      lines.add(
        'Бюджет: ${_fmtRub0.format(pace.budget)}, '
        'освоено ${_fmtRub0.format(pace.spent)} '
        '(${(pace.pctSpent * 100).toStringAsFixed(0)}%), '
        'остаток ${_fmtRub0.format(pace.remainingBudget)}.',
      );
    }

    if (pace.planToNow > 0) {
      final ratio = pace.pacePctNow;
      if (ratio < 0.9) {
        lines.add(
          'Темп: отстаём от плана на '
          '${_fmtRub0.format(pace.shortfallNow)} '
          '(${(ratio * 100).toStringAsFixed(0)}% плана на сегодня).',
        );
      } else if (ratio > 1.1) {
        lines.add(
          'Темп: идём быстрее плана — '
          '${(ratio * 100).toStringAsFixed(0)}% плана на сегодня.',
        );
      } else {
        lines.add(
          'Темп: в плане '
          '(${(ratio * 100).toStringAsFixed(0)}% плана на сегодня).',
        );
      }
    }

    final s = stats;
    if (s != null && (s.factExits > 0 || s.factOts > 0)) {
      final ots = s.factOts > 0
          ? ', OTS ${_fmtNum.format(s.factOts.round())}'
                '${s.factOtsIsEstimated ? ' (оценка)' : ''}'
          : '';
      lines.add('Выходов: ${_fmtNum.format(s.factExits)}$ots.');
    }

    final photoCoverage = coverage;
    if (photoCoverage != null && photoCoverage.totalSides > 0) {
      lines.add(
        'Фотоотчёты: ${photoCoverage.percent.toStringAsFixed(0)}% сторон '
        '(${photoCoverage.sidesWithPhoto} из ${photoCoverage.totalSides}).',
      );
    }

    return lines;
  }

  /// Сколько ошибок пришлось на каждого оператора — без поверхностей и
  /// формулировок: клиенту нужен масштаб, а не разбор.
  List<String> _operatorErrorLines(Map<String, int> issues) {
    final total = issues.values.fold<int>(0, (sum, count) => sum + count);
    final share = totalRequests > 0 ? total / totalRequests * 100 : 0;
    final sorted = issues.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return [
      'Всего ${_fmtNum.format(total)} из '
          '${_fmtNum.format(totalRequests)} попыток выхода '
          '(${share.toStringAsFixed(0)}%) не состоялись по причинам на стороне '
          'оператора.',
      for (final entry in sorted)
        '${entry.key} — ${_fmtNum.format(entry.value)} попыток',
    ];
  }

  List<String> _adviceLines(
    CampaignPaceSummary pace,
    List<BidRaiseRow> bids,
    Map<String, int> issues,
    Map<String, List<_PhotoTarget>> photos,
  ) {
    final lines = <String>[];

    if (pace.planToNow > 0 && pace.pacePctNow < 0.9) {
      final current = pace.currentDailyLimit;
      if (pace.dailyLimit > 0 &&
          (current == null || current < pace.dailyLimit)) {
        lines.add(
          '• Поднять суточный лимит до ${_fmtRub0.format(pace.dailyLimit)}'
          '${current != null && current > 0 ? ' (установлен ${_fmtRub0.format(current)})' : ''}'
          ', часовой — до ${_fmtRub0.format(pace.hourlyLimit)}: '
          'иначе остаток бюджета не успеет открутиться до конца срока.',
        );
      } else {
        lines.add(
          '• Лимит открутку не ограничивает — отставание не в нём. '
          'Смотрим ставки и доступность экранов ниже.',
        );
      }
    } else if (pace.planToNow > 0 && pace.pacePctNow > 1.1) {
      lines.add(
        '• Снизить суточный лимит до ${_fmtRub0.format(pace.dailyLimit)}: '
        'при текущем темпе бюджет закончится раньше срока размещения.',
      );
    }

    if (bids.isNotEmpty) {
      final maxRaise = bids
          .map((r) => r.recommendedBid)
          .fold<double>(0, (a, b) => b > a ? b : a);
      lines.add(
        '• Поднять ставки на ${bids.length} поверхностях, где показы '
        'проигрывают аукцион (до ${_fmtRub2.format(maxRaise)}) — '
        'таблица ниже.',
      );
    }

    if (issues.isNotEmpty) {
      final total = issues.values.fold<int>(0, (sum, count) => sum + count);
      final share = totalRequests > 0 ? total / totalRequests * 100 : 0;
      lines.add(
        '• Разобраться с операторами (${issues.length}): по их вине не '
        'состоялось ${_fmtNum.format(total)} показов — '
        '${share.toStringAsFixed(0)}% всех попыток выхода.',
      );
    }

    if (photos.isNotEmpty) {
      final screens = photos.values.fold<int>(0, (sum, l) => sum + l.length);
      lines.add(
        '• Запросить фотоотчёты по $screens экранам — список ниже.',
      );
    }

    if (lines.isEmpty) {
      lines.add('• Кампания идёт по плану, вмешательство не требуется.');
    }

    return lines;
  }

  /// Тот же текст, что на экране, плюс раскрытые списки — для отправки.
  String _buildText(
    CampaignPaceSummary pace,
    List<BidRaiseRow> bids,
    Map<String, int> issues,
    Map<String, List<_PhotoTarget>> photos,
  ) {
    final out = <String>[
      // Период — первой строкой: без него непонятно, за что цифры.
      _periodLine,
      '',
      'Как идёт кампания',
      ..._statusLines(pace),
      '',
      'Что предлагаем',
      ..._adviceLines(pace, bids, issues, photos),
    ];

    if (issues.isNotEmpty) {
      out
        ..add('')
        ..add('Ошибки на стороне оператора')
        ..addAll(_operatorErrorLines(issues));
    }

    if (bids.isNotEmpty) {
      out
        ..add('')
        ..add('Ставки к повышению (GID — сейчас — рекомендуем):');
      for (final row in bids) {
        out.add(
          '  ${row.inventoryGid} — ${_fmtRub2.format(row.lastBid)} — '
          '${_fmtRub2.format(row.recommendedBid)}'
          ' (проигрышей: ${row.lossCount})',
        );
      }
    }

    if (photos.isNotEmpty) {
      out
        ..add('')
        ..add('Экраны без фотоотчётов:');
      for (final entry in photos.entries) {
        out.add('  ${entry.key}');
        for (final target in entry.value) {
          out.add(
            '    ${target.label}'
            '${target.address.isEmpty ? '' : ' — ${target.address}'}'
            ' (${_fmtNum.format(target.shows)} показов)',
          );
        }
      }
    }

    return out.join('\n');
  }
}

/// Свёрнутая таблица «GID — новая ставка».
class _BidTile extends StatelessWidget {
  final List<BidRaiseRow> rows;

  const _BidTile({required this.rows});

  @override
  Widget build(BuildContext context) {
    return _Collapsible(
      title: 'Ставки к повышению: ${rows.length}',
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowHeight: 32,
          dataRowMinHeight: 30,
          dataRowMaxHeight: 36,
          columnSpacing: 20,
          columns: const [
            DataColumn(label: Text('GID')),
            DataColumn(label: Text('Сейчас'), numeric: true),
            DataColumn(label: Text('Рекомендуем'), numeric: true),
          ],
          rows: rows
              .map(
                (row) => DataRow(
                  cells: [
                    DataCell(Text(row.inventoryGid)),
                    DataCell(Text(_fmtRub2.format(row.lastBid))),
                    DataCell(
                      Text(
                        _fmtRub2.format(row.recommendedBid),
                        style: const TextStyle(
                          color: kAccent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}

/// Свёрнутый список экранов без фотоотчётов по операторам.
class _PhotosTile extends StatelessWidget {
  final Map<String, List<_PhotoTarget>> targets;

  const _PhotosTile({required this.targets});

  @override
  Widget build(BuildContext context) {
    final screens = targets.values.fold<int>(0, (sum, l) => sum + l.length);
    return _Collapsible(
      title: 'Экраны без фотоотчётов: $screens',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final entry in targets.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.key,
                    style: const TextStyle(
                      color: kTextPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  for (final target in entry.value)
                    Padding(
                      padding: const EdgeInsets.only(top: 2, left: 8),
                      child: Text(
                        '${target.label}'
                        '${target.address.isEmpty ? '' : ' — ${target.address}'}'
                        ' · ${_fmtNum.format(target.shows)} показов',
                        style: const TextStyle(
                          color: kTextSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Свёрнутый по умолчанию раздел без рамок и разделителей.
class _Collapsible extends StatelessWidget {
  final String title;
  final Widget child;

  const _Collapsible({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(left: 8, bottom: 8),
        title: Text(
          title,
          style: const TextStyle(
            color: kAccent,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        children: [child],
      ),
    );
  }
}
