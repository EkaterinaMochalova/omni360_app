import 'campaign_analytics.dart';

/// Разбивка по оператору/городу за один день — вложена в [DailyBreakdownRow].
class DailyOperatorCityRow {
  final String operatorName;
  final String city;
  final int total;
  final int success;
  final int bidLoss;
  final int operatorIssue;
  final double successSpend;

  const DailyOperatorCityRow({
    required this.operatorName,
    required this.city,
    required this.total,
    required this.success,
    required this.bidLoss,
    required this.operatorIssue,
    required this.successSpend,
  });

  double get successRate => total == 0 ? 0 : success / total * 100;
}

/// Итог по одному дню — используется на карточке "Сводная по дням".
class DailyBreakdownRow {
  final DateTime day;
  final int total;
  final int success;
  final int bidLoss;
  final int operatorIssue;
  final double successSpend;
  final List<DailyOperatorCityRow> breakdown;

  const DailyBreakdownRow({
    required this.day,
    required this.total,
    required this.success,
    required this.bidLoss,
    required this.operatorIssue,
    required this.successSpend,
    required this.breakdown,
  });

  double get successRate => total == 0 ? 0 : success / total * 100;
}

/// Одна рекламная поверхность (GID/адрес/сторона), где нужно поднять ставку.
class BidRaiseRow {
  final String inventoryGid;
  final String address;
  final String side;
  final String operatorName;
  final String city;
  final int lossCount;
  final double lastBid;
  final double bidFloor;

  const BidRaiseRow({
    required this.inventoryGid,
    required this.address,
    required this.side,
    required this.operatorName,
    required this.city,
    required this.lossCount,
    required this.lastBid,
    required this.bidFloor,
  });

  /// Небольшой запас 2%, чтобы не проигрывать по границе.
  double get recommendedBid => (bidFloor * 1.02);
}

/// Одна затронутая поверхность внутри группы причины/оператора/города —
/// полный список для передачи оператору.
class OperatorIssueDetailRow {
  final String inventoryGid;
  final String address;
  final String side;
  final int count;

  const OperatorIssueDetailRow({
    required this.inventoryGid,
    required this.address,
    required this.side,
    required this.count,
  });
}

/// Группа проблем оператора: причина + оператор + город, со сводкой и полным
/// списком затронутых поверхностей внутри.
class OperatorIssueGroupRow {
  final String reason;
  final String operatorName;
  final String city;
  final int count;
  final List<OperatorIssueDetailRow> details;

  const OperatorIssueGroupRow({
    required this.reason,
    required this.operatorName,
    required this.city,
    required this.count,
    required this.details,
  });

  int get distinctSurfaceCount => details.length;
}

class LossReport {
  final List<DailyBreakdownRow> dailyBreakdown;
  final List<BidRaiseRow> bidRaiseRows;
  final List<OperatorIssueGroupRow> operatorIssueGroups;

  const LossReport({
    required this.dailyBreakdown,
    required this.bidRaiseRows,
    required this.operatorIssueGroups,
  });

  factory LossReport.empty() => const LossReport(
    dailyBreakdown: [],
    bidRaiseRows: [],
    operatorIssueGroups: [],
  );
}

class LossReportBuilder {
  const LossReportBuilder._();

  static const String _unknownOperator = 'Неизвестный оператор';
  static const String _unknownCity = 'Неизвестный город';
  static const String _unknownReason = 'Причина неизвестна';

  static double _spend(CampaignImpressionRecord r) =>
      r.chargedPrice ?? r.price ?? 0;

  static DateTime _dayOf(DateTime time) {
    final local = time.toLocal();
    return DateTime(local.year, local.month, local.day);
  }

  static LossReport build(List<CampaignImpressionRecord> records) {
    if (records.isEmpty) return LossReport.empty();

    return LossReport(
      dailyBreakdown: _buildDailyBreakdown(records),
      bidRaiseRows: _buildBidRaiseRows(records),
      operatorIssueGroups: _buildOperatorIssueGroups(records),
    );
  }

  static List<DailyBreakdownRow> _buildDailyBreakdown(
    List<CampaignImpressionRecord> records,
  ) {
    final byDay = <DateTime, List<CampaignImpressionRecord>>{};
    for (final r in records) {
      if (r.showTime == null) continue;
      byDay.putIfAbsent(_dayOf(r.showTime!), () => []).add(r);
    }

    final days = byDay.keys.toList()..sort();
    return days.map((day) {
      final dayRecords = byDay[day]!;
      final byOperatorCity = <(String, String), List<CampaignImpressionRecord>>{};
      for (final r in dayRecords) {
        final operator = r.displayOwnerName ?? _unknownOperator;
        final city = r.city ?? _unknownCity;
        byOperatorCity.putIfAbsent((operator, city), () => []).add(r);
      }

      final breakdown =
          byOperatorCity.entries.map((entry) {
            final rows = entry.value;
            final (operatorName, city) = entry.key;
            return DailyOperatorCityRow(
              operatorName: operatorName,
              city: city,
              total: rows.length,
              success: rows.where((r) => r.isWin).length,
              bidLoss: rows
                  .where((r) => r.isLoss && classifyLoss(r) == LossCategory.lowBid)
                  .length,
              operatorIssue: rows
                  .where(
                    (r) =>
                        r.isLoss && classifyLoss(r) == LossCategory.operatorIssue,
                  )
                  .length,
              successSpend: rows
                  .where((r) => r.isWin)
                  .fold(0.0, (sum, r) => sum + _spend(r)),
            );
          }).toList()
            ..sort((a, b) => b.total.compareTo(a.total));

      return DailyBreakdownRow(
        day: day,
        total: dayRecords.length,
        success: dayRecords.where((r) => r.isWin).length,
        bidLoss: dayRecords
            .where((r) => r.isLoss && classifyLoss(r) == LossCategory.lowBid)
            .length,
        operatorIssue: dayRecords
            .where(
              (r) => r.isLoss && classifyLoss(r) == LossCategory.operatorIssue,
            )
            .length,
        successSpend: dayRecords
            .where((r) => r.isWin)
            .fold(0.0, (sum, r) => sum + _spend(r)),
        breakdown: breakdown,
      );
    }).toList();
  }

  static List<BidRaiseRow> _buildBidRaiseRows(
    List<CampaignImpressionRecord> records,
  ) {
    final lossRecords = records.where(
      (r) => r.isLoss && classifyLoss(r) == LossCategory.lowBid,
    );

    final byKey =
        <(String, String, String, String, String), List<CampaignImpressionRecord>>{};
    for (final r in lossRecords) {
      final key = (
        r.inventoryGid ?? '',
        r.address ?? '',
        r.side ?? '',
        r.displayOwnerName ?? _unknownOperator,
        r.city ?? _unknownCity,
      );
      byKey.putIfAbsent(key, () => []).add(r);
    }

    final rows = byKey.entries.map((entry) {
      final rows = entry.value;
      final (inventoryGid, address, side, operatorName, city) = entry.key;
      // Последняя по времени запись — самая свежая ставка/минимум.
      final latest = [...rows]..sort(
        (a, b) => (a.showTime ?? DateTime(0)).compareTo(b.showTime ?? DateTime(0)),
      );
      final last = latest.last;

      return BidRaiseRow(
        inventoryGid: inventoryGid,
        address: address,
        side: side,
        operatorName: operatorName,
        city: city,
        lossCount: rows.length,
        lastBid: last.bid ?? 0,
        bidFloor: last.bidFloor ?? 0,
      );
    }).toList()..sort((a, b) => b.lossCount.compareTo(a.lossCount));

    return rows;
  }

  static List<OperatorIssueGroupRow> _buildOperatorIssueGroups(
    List<CampaignImpressionRecord> records,
  ) {
    final issueRecords = records.where(
      (r) => r.isLoss && classifyLoss(r) == LossCategory.operatorIssue,
    );

    final byGroupKey = <(String, String, String), List<CampaignImpressionRecord>>{};
    for (final r in issueRecords) {
      final reason =
          r.failureReasonMessage ?? r.failureReasonType ?? _unknownReason;
      final key = (reason, r.displayOwnerName ?? _unknownOperator, r.city ?? _unknownCity);
      byGroupKey.putIfAbsent(key, () => []).add(r);
    }

    final groups = byGroupKey.entries.map((entry) {
      final groupRecords = entry.value;
      final (reason, operatorName, city) = entry.key;

      final byDetailKey = <(String, String, String), List<CampaignImpressionRecord>>{};
      for (final r in groupRecords) {
        final detailKey = (r.inventoryGid ?? '', r.address ?? '', r.side ?? '');
        byDetailKey.putIfAbsent(detailKey, () => []).add(r);
      }

      final details =
          byDetailKey.entries.map((detailEntry) {
            final (inventoryGid, address, side) = detailEntry.key;
            return OperatorIssueDetailRow(
              inventoryGid: inventoryGid,
              address: address,
              side: side,
              count: detailEntry.value.length,
            );
          }).toList()
            ..sort((a, b) => b.count.compareTo(a.count));

      return OperatorIssueGroupRow(
        reason: reason,
        operatorName: operatorName,
        city: city,
        count: groupRecords.length,
        details: details,
      );
    }).toList()..sort((a, b) => b.count.compareTo(a.count));

    return groups;
  }
}
