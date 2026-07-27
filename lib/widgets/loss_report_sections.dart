import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../main.dart';
import '../models/loss_report.dart';
import 'card_section.dart';

final _fmtRub = NumberFormat.currency(
  locale: 'ru_RU',
  symbol: '₽',
  decimalDigits: 2,
);
final _fmtDate = DateFormat('dd.MM.yyyy');

String _pct(double value) => '${value.toStringAsFixed(1)}%';

/// Сводная по дням: итог за день + свёрнутая по умолчанию разбивка по
/// оператору/городу (нативная сворачиваемость Flutter вместо имитации
/// Excel-группировки).
class DailyBreakdownSection extends StatelessWidget {
  final List<DailyBreakdownRow> rows;

  const DailyBreakdownSection({super.key, required this.rows});

  @override
  Widget build(BuildContext context) {
    return CardSection(
      title: 'Сводная по дням',
      subtitle: 'Итог за день, разбивка по оператору/городу — по клику',
      child: rows.isEmpty
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Нет данных за выбранный период.',
                style: TextStyle(color: kTextSecondary),
              ),
            )
          : Column(
              children: rows.map((row) => _DayTile(row: row)).toList(),
            ),
    );
  }
}

class _DayTile extends StatelessWidget {
  final DailyBreakdownRow row;

  const _DayTile({required this.row});

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(left: 12, bottom: 8),
        title: Row(
          children: [
            SizedBox(
              width: 90,
              child: Text(
                _fmtDate.format(row.day),
                style: const TextStyle(
                  color: kTextPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
            Expanded(
              child: Text(
                '${row.total} показов • ${_pct(row.successRate)} успешных',
                style: const TextStyle(color: kTextSecondary, fontSize: 12),
              ),
            ),
            if (row.bidLoss > 0)
              _CountBadge(label: 'ставка', count: row.bidLoss, color: Colors.orange),
            if (row.operatorIssue > 0) ...[
              const SizedBox(width: 6),
              _CountBadge(label: 'оператор', count: row.operatorIssue, color: Colors.red),
            ],
          ],
        ),
        children: row.breakdown
            .map(
              (b) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Text(
                        '${b.operatorName} · ${b.city}',
                        style: const TextStyle(fontSize: 12, color: kTextPrimary),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        '${b.total} показов, ${_pct(b.successRate)}',
                        style: const TextStyle(fontSize: 12, color: kTextSecondary),
                      ),
                    ),
                    Text(
                      'ставка: ${b.bidLoss} · оператор: ${b.operatorIssue}',
                      style: const TextStyle(fontSize: 11, color: kTextSecondary),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  final String label;
  final int count;
  final Color color;

  const _CountBadge({required this.label, required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '$label: $count',
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// Показы, проигранные в аукционе из-за низкой ставки — по одной строке на
/// рекламную поверхность (GID/адрес/сторона).
class BidRaiseReportSection extends StatelessWidget {
  final List<BidRaiseRow> rows;

  const BidRaiseReportSection({super.key, required this.rows});

  @override
  Widget build(BuildContext context) {
    return CardSection(
      title: 'Поднять ставки',
      subtitle: 'Проигрыши в аукционе из-за ставки ниже минимальной',
      child: rows.isEmpty
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Проигрышей по ставке не найдено.',
                style: TextStyle(color: kTextSecondary),
              ),
            )
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowHeight: 36,
                dataRowMinHeight: 36,
                dataRowMaxHeight: 44,
                columns: const [
                  DataColumn(label: Text('GID')),
                  DataColumn(label: Text('Адрес')),
                  DataColumn(label: Text('Оператор')),
                  DataColumn(label: Text('Город')),
                  DataColumn(label: Text('Проигрышей'), numeric: true),
                  DataColumn(label: Text('Ставка'), numeric: true),
                  DataColumn(label: Text('Мин. ставка'), numeric: true),
                  DataColumn(label: Text('Выигравшая'), numeric: true),
                  DataColumn(label: Text('Рекомендуем')),
                ],
                rows: rows
                    .map(
                      (r) => DataRow(
                        cells: [
                          DataCell(Text('${r.inventoryGid} ${r.side}')),
                          DataCell(
                            SizedBox(
                              width: 220,
                              child: Text(r.address, overflow: TextOverflow.ellipsis),
                            ),
                          ),
                          DataCell(Text(r.operatorName)),
                          DataCell(Text(r.city)),
                          DataCell(Text('${r.lossCount}')),
                          DataCell(Text(_fmtRub.format(r.lastBid))),
                          DataCell(Text(_fmtRub.format(r.bidFloor))),
                          DataCell(
                            Text(
                              r.basedOnWinningBid
                                  ? _fmtRub.format(r.maxWinningBid)
                                  : '—',
                            ),
                          ),
                          DataCell(
                            Tooltip(
                              message: r.basedOnWinningBid
                                  ? 'Максимальная выигравшая ставка '
                                        '${_fmtRub.format(r.maxWinningBid)} '
                                        '+ ${BidRaiseRow.bidStep}'
                                  : 'Выигравшая ставка в причине отклонения не '
                                        'указана — считаем от минимальной ставки',
                              child: Text(
                                '${_fmtRub.format(r.recommendedBid)}'
                                '  (+${_fmtRub.format(r.raiseBy)})',
                                style: TextStyle(
                                  color: r.basedOnWinningBid
                                      ? kAccent
                                      : kTextSecondary,
                                  fontWeight: FontWeight.w600,
                                ),
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

/// Ошибки на стороне оператора/SSP/плеера, сгруппированные по причине —
/// сводка + полный список затронутых поверхностей внутри каждой группы.
class OperatorIssueReportSection extends StatelessWidget {
  final List<OperatorIssueGroupRow> groups;

  const OperatorIssueReportSection({super.key, required this.groups});

  @override
  Widget build(BuildContext context) {
    return CardSection(
      title: 'К оператору',
      subtitle:
          'Показ не подтверждён SSP/плеером, неизвестная причина и т.п. — с полным списком GID',
      child: groups.isEmpty
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Проблем на стороне оператора не найдено.',
                style: TextStyle(color: kTextSecondary),
              ),
            )
          : Column(
              children: groups.map((g) => _OperatorIssueTile(group: g)).toList(),
            ),
    );
  }
}

class _OperatorIssueTile extends StatelessWidget {
  final OperatorIssueGroupRow group;

  const _OperatorIssueTile({required this.group});

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(left: 12, bottom: 8),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              group.reason,
              style: const TextStyle(
                color: kTextPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${group.operatorName} · ${group.city} · ${group.count} показов · '
              '${group.distinctSurfaceCount} поверхностей',
              style: const TextStyle(color: kTextSecondary, fontSize: 12),
            ),
          ],
        ),
        children: group.details
            .map(
              (d) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${d.inventoryGid}${d.side.isNotEmpty ? ' ${d.side}' : ''} — ${d.address}',
                        style: const TextStyle(fontSize: 12, color: kTextPrimary),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '${d.count}',
                      style: const TextStyle(fontSize: 12, color: kTextSecondary),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}
