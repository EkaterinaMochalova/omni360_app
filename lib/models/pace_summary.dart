import '../utils/broadcast_schedule.dart';
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

  /// Часы вещания, оставшиеся до конца кампании (с учётом расписания и того,
  /// что часть сегодняшнего дня уже прошла). 0 — если вещать больше негде.
  final double broadcastHoursLeft;

  /// Дни, в которые кампания реально вещает, до конца срока включительно.
  final int broadcastDaysLeft;

  /// Задано ли у кампании расписание. Если нет — лимиты считаны из круглых
  /// суток, и это стоит показать пользователю, а не выдавать за точный расчёт.
  final bool scheduleKnown;

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
    this.broadcastHoursLeft = 0,
    this.broadcastDaysLeft = 0,
    this.scheduleKnown = false,
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
    // Расписание из детального ответа: в списочном timeSettings нет, поэтому
    // экран догружает его отдельно и передаёт сюда.
    List<TimeSlot>? scheduleOverride,
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

    // Остаток вещания до конца кампании: складываем фактическую длительность
    // слотов по каждому дню (за сегодня — только ещё не прошедшее время).
    final schedule = scheduleOverride ?? campaign.timeSettings;
    final left = broadcastHoursAndDays(schedule, today, end);
    final broadcastHoursLeft = left.hours;
    final broadcastDaysLeft = left.days;

    // Суточный лимит делим на дни, когда кампания действительно вещает:
    // если она стоит по выходным, размазывать остаток по календарным дням
    // значит недоливать в рабочие.
    final dailyLimit = broadcastDaysLeft > 0
        ? remaining / broadcastDaysLeft
        : (daysLeft == 0 ? 0.0 : remaining / daysLeft);
    final hourlyLimit = broadcastHoursLeft > 0
        ? remaining / broadcastHoursLeft
        : 0.0;

    return CampaignPaceSummary(
      broadcastHoursLeft: broadcastHoursLeft,
      broadcastDaysLeft: broadcastDaysLeft,
      scheduleKnown: hasSchedule(schedule),
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
