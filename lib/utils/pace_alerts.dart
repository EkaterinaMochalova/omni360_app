import 'dart:math';
import '../models/campaign.dart';

enum PaceType { over, under, noExits }

class PaceAlert {
  final String metric;
  final PaceType type;
  final double pct;
  const PaceAlert(this.metric, this.type, this.pct);
}

/// Возвращает (startHour, endHour) активных часов кампании на сегодня.
/// Если расписание не задано — fallback 0–24 (весь день).
/// Если кампания сегодня не активна — возвращает null.
(int start, int end)? _activeHoursToday(Campaign campaign) {
  final slots = campaign.timeSettings;
  if (slots == null || slots.isEmpty) return (0, 24); // нет расписания — весь день

  final today = DateTime.now().weekday; // 1=Пн…7=Вс
  final todaySlots = slots.where((s) => s.dayOfWeek == today).toList();
  if (todaySlots.isEmpty) return null; // кампания не работает сегодня

  final start = todaySlots.map((s) => s.startHour).reduce(min);
  final end = todaySlots.map((s) => s.endHour).reduce(max);
  return (start, end);
}

/// Доля прошедшего дня в рамках активных часов кампании.
/// 0 = вне активного окна (слишком рано, поздно или не тот день).
double expectedDayFraction(Campaign campaign) {
  final hours = _activeHoursToday(campaign);
  if (hours == null) return 0;
  final (start, end) = hours;
  final total = (end - start).toDouble();
  if (total <= 0) return 0;

  final now = DateTime.now();
  if (now.hour >= end || now.hour < start) return 0;

  final elapsed = (now.hour + now.minute / 60 - start).clamp(0.0, total);
  if (elapsed < 0.5) return 0;
  return elapsed / total;
}

/// Проверяет, находится ли текущее время в активном окне кампании.
bool isWithinSchedule(Campaign campaign) {
  final hours = _activeHoursToday(campaign);
  if (hours == null) return false;
  final (start, end) = hours;
  final h = DateTime.now().hour;
  return h >= start && h < end;
}

List<PaceAlert> buildAlerts(Campaign campaign, CampaignStats s) {
  final alerts = <PaceAlert>[];
  final dayFraction = expectedDayFraction(campaign);
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

  // Выходы — только если план задан
  final planHourlyExits = (campaign.exits ?? 0) / 14;
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
      isWithinSchedule(campaign) && s.factExits > 0 && s.hourlyExitsFact == 0) {
    alerts.add(PaceAlert('Выходы', PaceType.noExits, 0));
  }

  return alerts;
}
