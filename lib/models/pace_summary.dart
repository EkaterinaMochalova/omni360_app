import '../utils/pace_alerts.dart';
import 'campaign.dart';

/// Индикация темпа освоения бюджета (см. легенду kontrazud_pacing.xlsx):
/// красный <70% плана к сегодня, жёлтый 70–95%, зелёный ≥95%.
enum PaceStatus { red, yellow, green }

/// Сводная строка по бюджету/темпу одной кампании — как в сводной таблице
/// "Сводка по кампаниям — темп освоения бюджета".
class CampaignPaceSummary {
  final String id;
  final String name;
  final DateTime? startDate;
  final DateTime? endDate;
  final double budget;
  final double spent;
  final int totalDays;
  final int daysPassed;
  final int daysLeft;
  final double planToDate;
  final double paceAmount;
  final double dailyLimit;
  final double hourlyLimit;

  const CampaignPaceSummary({
    required this.id,
    required this.name,
    required this.startDate,
    required this.endDate,
    required this.budget,
    required this.spent,
    required this.totalDays,
    required this.daysPassed,
    required this.daysLeft,
    required this.planToDate,
    required this.paceAmount,
    required this.dailyLimit,
    required this.hourlyLimit,
  });

  double get pctSpent => budget <= 0 ? 0 : spent / budget;

  /// Темп, % от плана к сегодня. 100% = ровно по плану.
  double get pacePct => planToDate <= 0 ? 0 : spent / planToDate;

  double get remainingBudget => budget - spent;

  PaceStatus get status {
    if (pacePct < 0.70) return PaceStatus.red;
    if (pacePct < 0.95) return PaceStatus.yellow;
    return PaceStatus.green;
  }

  static DateTime? _parseDate(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    return DateTime.tryParse(raw.trim());
  }

  static int _inclusiveDays(DateTime start, DateTime end) {
    final s = DateTime(start.year, start.month, start.day);
    final e = DateTime(end.year, end.month, end.day);
    final diff = e.difference(s).inDays + 1;
    return diff < 0 ? 0 : diff;
  }

  factory CampaignPaceSummary.fromCampaign(
    Campaign campaign,
    DateTime today, {
    double? spentOverride,
  }) {
    final start = _parseDate(campaign.startDate);
    final end = _parseDate(campaign.endDate);
    final budget = campaign.budget ?? 0;
    final spent = spentOverride ?? (campaign.spent ?? 0);

    if (start == null || end == null || budget <= 0) {
      return CampaignPaceSummary(
        id: campaign.id,
        name: campaign.name,
        startDate: start,
        endDate: end,
        budget: budget,
        spent: spent,
        totalDays: 0,
        daysPassed: 0,
        daysLeft: 0,
        planToDate: 0,
        paceAmount: 0,
        dailyLimit: 0,
        hourlyLimit: 0,
      );
    }

    // Формулы — по легенде kontrazud_pacing.xlsx:
    // Дней прошло = сегодня − начало + 1, ограничено [0; Дней всего].
    // Дней осталось = конец − сегодня + 1, не меньше 0.
    final totalDays = _inclusiveDays(start, end);
    final daysPassed = _inclusiveDays(start, today).clamp(0, totalDays);
    final daysLeft = _inclusiveDays(today, end);

    final planToDate = totalDays == 0 ? 0.0 : budget / totalDays * daysPassed;
    final remaining = (budget - spent).clamp(0.0, double.infinity);
    final dailyLimit = daysLeft == 0 ? 0.0 : remaining / daysLeft;

    final hours = activeHoursToday(campaign);
    final hoursPerDay = (hours == null || hours.$2 - hours.$1 <= 0)
        ? 24
        : hours.$2 - hours.$1;
    final hourlyLimit = dailyLimit / hoursPerDay;

    return CampaignPaceSummary(
      id: campaign.id,
      name: campaign.name,
      startDate: start,
      endDate: end,
      budget: budget,
      spent: spent,
      totalDays: totalDays,
      daysPassed: daysPassed,
      daysLeft: daysLeft,
      planToDate: planToDate,
      paceAmount: spent - planToDate,
      dailyLimit: dailyLimit,
      hourlyLimit: hourlyLimit,
    );
  }
}
