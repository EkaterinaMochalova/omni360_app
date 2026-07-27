import '../models/campaign.dart';
import 'broadcast_schedule.dart';

enum PaceType { over, under, noExits }

class PaceAlert {
  final String metric;
  final PaceType type;
  final double pct;
  const PaceAlert(this.metric, this.type, this.pct);
}

/// Доля прошедшего вещания за сегодня, 0..1.
/// 0 — вне окна вещания (слишком рано, поздно или сегодня не вещаем).
///
/// Считается по фактической длительности слотов: перерыв внутри дня не должен
/// попадать в знаменатель, иначе доля прошедшего занижается и алерты врут.
double expectedDayFraction(Campaign campaign, {List<TimeSlot>? schedule}) {
  final slots = schedule ?? campaign.timeSettings;
  final now = DateTime.now();
  if (!isWithinBroadcast(slots, now)) return 0;

  final total = broadcastSecondsOnDate(slots, now);
  if (total <= 0) return 0;

  final nowSecond = now.hour * secondsPerHour + now.minute * 60 + now.second;
  final elapsed = total - broadcastSecondsOnDate(slots, now, fromSecond: nowSecond);
  if (elapsed < 1800) return 0; // меньше получаса — статистика ещё ни о чём
  return elapsed / total;
}

/// Находится ли текущее время в окне вещания кампании.
bool isWithinSchedule(Campaign campaign, {List<TimeSlot>? schedule}) =>
    isWithinBroadcast(schedule ?? campaign.timeSettings, DateTime.now());

List<PaceAlert> buildAlerts(
  Campaign campaign,
  CampaignStats s, {
  List<TimeSlot>? schedule,
}) {
  final alerts = <PaceAlert>[];
  final dayFraction = expectedDayFraction(campaign, schedule: schedule);
  if (dayFraction <= 0) return alerts;

  void check(String label, double plan, double fact) {
    if (plan <= 0 || fact <= 0) return;
    final pace = fact / (plan * dayFraction);
    if (pace > 1.25) {
      alerts.add(PaceAlert(label, PaceType.over, (pace - 1) * 100));
    } else if (pace < 0.7) {
      alerts.add(PaceAlert(label, PaceType.under, (1 - pace) * 100));
    }
  }

  // Бюджет
  if (s.hourlyBudgetPlan > 0) {
    final pace = s.hourlyBudgetFact / s.hourlyBudgetPlan;
    if (pace > 1.25) {
      alerts.add(PaceAlert('Бюджет/час', PaceType.over, (pace - 1) * 100));
    } else if (pace < 0.7) {
      alerts.add(PaceAlert('Бюджет/час', PaceType.under, (1 - pace) * 100));
    }
  } else {
    check('Бюджет', campaign.dailyBudget ?? 0, s.factDailyBudget);
  }

  // OTS — только если план задан на уровне кампании
  if ((campaign.ots ?? 0) > 0) {
    if (s.hourlyOtsPlan > 0 && s.hourlyOtsFact > 0) {
      final pace = s.hourlyOtsFact / s.hourlyOtsPlan;
      if (pace > 1.25) {
        alerts.add(PaceAlert('OTS/час', PaceType.over, (pace - 1) * 100));
      } else if (pace < 0.7) {
        alerts.add(PaceAlert('OTS/час', PaceType.under, (1 - pace) * 100));
      }
    } else if (s.factOts > 0) {
      check('OTS', s.planOts, s.factOts);
    }
  }

  // Выходы — только если план задан. exits — выходы за всю кампанию, поэтому
  // делим на часы вещания за весь срок, а не на зашитые 14 часов суток.
  final totalHours = totalBroadcastHours(campaign, scheduleOverride: schedule);
  final planHourlyExits = (totalHours != null && totalHours > 0)
      ? (campaign.exits ?? 0) / totalHours
      : 0.0;
  if (planHourlyExits > 0 && s.hourlyExitsFact > 0) {
    final pace = s.hourlyExitsFact / planHourlyExits;
    if (pace > 1.25) {
      alerts.add(PaceAlert('Выходы/час', PaceType.over, (pace - 1) * 100));
    } else if (pace < 0.7) {
      alerts.add(PaceAlert('Выходы/час', PaceType.under, (1 - pace) * 100));
    }
  }

  // Нет выходов за последний час — кампания активна и в расписании, но тихо
  if (campaign.isActive && !campaign.isNotOnSchedule &&
      isWithinSchedule(campaign, schedule: schedule) &&
      s.factExits > 0 && s.hourlyExitsFact == 0) {
    alerts.add(PaceAlert('Выходы', PaceType.noExits, 0));
  }

  return alerts;
}
