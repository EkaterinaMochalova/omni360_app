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

  /// Сколько по плану должно быть потрачено к текущему моменту — по доле
  /// прошедшего эфирного времени, а не по целым дням.
  final double planToNow;

  /// Часы вещания, оставшиеся до конца кампании (с учётом расписания и того,
  /// что часть сегодняшнего дня уже прошла). 0 — если вещать больше негде.
  final double broadcastHoursLeft;

  /// Дни, в которые кампания реально вещает, до конца срока включительно.
  final int broadcastDaysLeft;

  /// Удалось ли выяснить расписание. false — данные не загрузились, и лимиты
  /// посчитаны наугад из круглых суток; это надо показать пользователю.
  final bool scheduleResolved;

  /// Есть ли у кампании ограничения по времени. false при
  /// [scheduleResolved] == true означает «идёт круглые сутки» — это
  /// достоверный расчёт, а не отсутствие данных.
  final bool hasTimeRestrictions;

  /// Расписание ещё грузится. Отличаем от неудачи: пока ждём, помечать цифру
  /// как ненадёжную рано — она просто ещё не окончательная.
  final bool scheduleLoading;

  /// Лимиты, выставленные в кампании сейчас, — чтобы было видно, надо
  /// рекомендуемый поднимать или опускать. null — лимит не задан.
  final double? currentDailyLimit;
  final double? currentHourlyLimit;

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
    this.planToNow = 0,
    this.broadcastHoursLeft = 0,
    this.broadcastDaysLeft = 0,
    this.scheduleResolved = false,
    this.hasTimeRestrictions = false,
    this.scheduleLoading = false,
    this.currentDailyLimit,
    this.currentHourlyLimit,
  });

  /// Во сколько раз рекомендуемый лимит отличается от установленного.
  /// null — сравнивать не с чем. >1 — надо поднимать, <1 — снижать.
  double? get dailyLimitFactor =>
      (currentDailyLimit != null && currentDailyLimit! > 0 && dailyLimit > 0)
      ? dailyLimit / currentDailyLimit!
      : null;

  double? get hourlyLimitFactor =>
      (currentHourlyLimit != null && currentHourlyLimit! > 0 && hourlyLimit > 0)
      ? hourlyLimit / currentHourlyLimit!
      : null;

  double get pctSpent => budget <= 0 ? 0 : spent / budget;

  /// Темп, % от плана к сегодня. 100% = ровно по плану.
  double get pacePct => planToDate <= 0 ? 0 : spent / planToDate;

  double get remainingBudget => budget - spent;

  /// Сколько не хватает до плана прямо сейчас. Отрицательное — перелив.
  double get shortfallNow => planToNow - spent;

  /// Темп относительно плана на текущий момент. 1.0 = ровно по плану.
  double get pacePctNow => planToNow <= 0 ? 0 : spent / planToNow;

  /// Статус считаем от плана на текущий момент, а не от плана к концу дня:
  /// иначе утром любая кампания красная просто потому, что эфир ещё впереди.
  PaceStatus get status {
    if (pacePctNow < 0.70) return PaceStatus.red;
    if (pacePctNow < 0.95) return PaceStatus.yellow;
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
    // экран догружает его отдельно и передаёт сюда. null — загрузить не
    // удалось (это не то же самое, что расписание без ограничений).
    BroadcastSchedule? schedule,
    bool scheduleLoading = false,
    double? currentHourlyLimit,
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
    final slots = schedule?.slots ?? campaign.timeSettings;
    final left = broadcastHoursAndDays(slots, today, end);
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

    // План «на сейчас» — по доле уже прошедшего эфирного времени, а не по
    // целым дням: «План к сегодня» скачет ступенькой в полночь и весь день
    // показывает, что мы отстаём, хотя эфир ещё впереди.
    final spentAll = broadcastHoursAndDays(slots, start, end, fromTimeOfDay: false);
    final totalBroadcast = spentAll.hours;
    final elapsedBroadcast = (totalBroadcast - broadcastHoursLeft)
        .clamp(0.0, totalBroadcast);
    final planToNow = totalBroadcast > 0
        ? budget * (elapsedBroadcast / totalBroadcast)
        : planToDate;

    return CampaignPaceSummary(
      planToNow: planToNow,
      broadcastHoursLeft: broadcastHoursLeft,
      broadcastDaysLeft: broadcastDaysLeft,
      scheduleResolved: schedule != null || hasSchedule(campaign.timeSettings),
      hasTimeRestrictions: hasSchedule(slots),
      scheduleLoading: scheduleLoading,
      currentDailyLimit: campaign.dailyBudget,
      currentHourlyLimit: currentHourlyLimit,
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
