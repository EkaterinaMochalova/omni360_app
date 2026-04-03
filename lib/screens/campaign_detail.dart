import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../main.dart';
import '../providers/campaigns_provider.dart';
import '../models/campaign.dart';
import '../widgets/stats_chart.dart';

class CampaignDetailScreen extends ConsumerWidget {
  final String campaignId;

  const CampaignDetailScreen({super.key, required this.campaignId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(campaignDetailProvider(campaignId));
    final stats = ref.watch(campaignStatsProvider(campaignId));

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: kTextPrimary, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: detail.maybeWhen(
          data: (c) => Text(
            c.name,
            style: const TextStyle(
                color: kTextPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 16),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          orElse: () =>
              const Text('Кампания', style: TextStyle(color: kTextPrimary)),
        ),
      ),
      body: detail.when(
        loading: () =>
            const Center(child: CircularProgressIndicator(color: kAccent)),
        error: (e, _) => Center(
          child: Text('Ошибка: $e',
              style: const TextStyle(color: kTextSecondary)),
        ),
        data: (campaign) => SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _StatusCard(campaign: campaign),
              const SizedBox(height: 12),
              _DatesCard(campaign: campaign),
              const SizedBox(height: 12),
              // Plan / Fact card — passes stats when loaded
              stats.maybeWhen(
                data: (s) => _PlanFactCard(campaign: campaign, stats: s),
                orElse: () => _PlanFactCard(campaign: campaign, stats: null),
              ),
              const SizedBox(height: 12),
              // Daily chart
              stats.maybeWhen(
                data: (s) => s.daily.isNotEmpty
                    ? _ChartCard(stats: s)
                    : const SizedBox.shrink(),
                orElse: () => const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Status card ───────────────────────────────────────────────────────────────

class _StatusCard extends StatelessWidget {
  final Campaign campaign;
  const _StatusCard({required this.campaign});

  @override
  Widget build(BuildContext context) {
    final fg = _statusStyle(campaign.status).$3;
    final label = campaign.displayStatus;
    return _Card(
      child: Row(
        children: [
          Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: fg, shape: BoxShape.circle)),
          const SizedBox(width: 10),
          Text(label,
              style: TextStyle(
                  color: fg, fontWeight: FontWeight.w600, fontSize: 14)),
          const Spacer(),
          if (campaign.type != null)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                  color: kAccentLight,
                  borderRadius: BorderRadius.circular(20)),
              child: Text(campaign.type!,
                  style: const TextStyle(color: kAccent, fontSize: 12)),
            ),
        ],
      ),
    );
  }

  static (String, Color, Color) _statusStyle(String status) =>
      switch (status.toUpperCase()) {
        'RUNNING' || 'ACTIVE' => (
            'Активна',
            const Color(0xFFE8F5E9),
            const Color(0xFF2E7D32)
          ),
        'PAUSED' => (
            'На паузе',
            const Color(0xFFFFF3E0),
            const Color(0xFFE65100)
          ),
        'NEW' => (
            'Новая',
            const Color(0xFFE3F2FD),
            const Color(0xFF1565C0)
          ),
        'OFF_SCHEDULE' => (
            'Не в графике',
            const Color(0xFFFFFDE7),
            const Color(0xFFF9A825)
          ),
        'BUDGET_EXHAUSTED' || 'STOPPED' => (
            'Бюджет исчерпан',
            const Color(0xFFFFEBEE),
            const Color(0xFFC62828)
          ),
        'COMPLETED' => (
            'Завершена',
            const Color(0xFFF5F5F5),
            const Color(0xFF757575)
          ),
        _ => (
            status.isNotEmpty ? status : 'Неизвестно',
            const Color(0xFFF5F5F5),
            const Color(0xFF757575)
          ),
      };
}

// ── Dates card ────────────────────────────────────────────────────────────────

class _DatesCard extends StatelessWidget {
  final Campaign campaign;
  const _DatesCard({required this.campaign});

  @override
  Widget build(BuildContext context) {
    if (campaign.startDate == null && campaign.endDate == null) {
      return const SizedBox.shrink();
    }
    return _Card(
      child: Row(
        children: [
          const Icon(Icons.calendar_today_outlined,
              size: 16, color: kTextSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${campaign.startDate ?? '—'} – ${campaign.endDate ?? '—'}',
              style: const TextStyle(color: kTextPrimary, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Plan / Fact card ──────────────────────────────────────────────────────────

class _PlanFactCard extends StatelessWidget {
  final Campaign campaign;
  final CampaignStats? stats;

  const _PlanFactCard({required this.campaign, required this.stats});

  @override
  Widget build(BuildContext context) {
    final fmtRub = NumberFormat.currency(
        locale: 'ru_RU', symbol: '₽', decimalDigits: 0);
    final fmtNum =
        NumberFormat.decimalPattern('ru_RU');

    final rows = <Widget>[];

    final s = stats; // non-nullable local for null-safety

    // ПЛАН всегда из данных кампании (detail endpoint)
    // impression-stats используем только для ФАКТ
    final planBudget = campaign.budget;
    final planDaily = campaign.dailyBudget;
    final planOts = campaign.ots;

    // Бюджет
    if (planBudget != null && planBudget > 0) {
      final factBudget = (s != null && s.factBudget > 0) ? s.factBudget : null;
      rows.add(_PlanFactRow(
        label: 'Бюджет',
        plan: fmtRub.format(planBudget),
        fact: factBudget != null ? fmtRub.format(factBudget) : null,
        ratio: factBudget != null ? factBudget / planBudget : null,
      ));
    }

    // В день
    if (planDaily != null && planDaily > 0) {
      final factDaily =
          (s != null && s.factDailyBudget > 0) ? s.factDailyBudget : null;
      rows.add(_PlanFactRow(
        label: 'В день',
        plan: fmtRub.format(planDaily),
        fact: factDaily != null ? fmtRub.format(factDaily) : null,
        ratio: factDaily != null ? factDaily / planDaily : null,
      ));
    }

    // OTS — показываем если есть план ИЛИ факт
    final factOts = (s != null && s.factOts > 0) ? s.factOts : null;
    if ((planOts != null && planOts > 0) || factOts != null) {
      rows.add(_PlanFactRow(
        label: 'OTS',
        plan: (planOts != null && planOts > 0) ? fmtNum.format(planOts) : '—',
        fact: factOts != null ? fmtNum.format(factOts) : null,
        ratio: (factOts != null && planOts != null && planOts > 0)
            ? factOts / planOts
            : null,
      ));
    }

    // Выходы (totalCountShowed)
    if (s != null && s.factExits > 0) {
      final planExits = campaign.exits;
      rows.add(_PlanFactRow(
        label: 'Выходы',
        plan: planExits != null && planExits > 0
            ? fmtNum.format(planExits)
            : '—',
        fact: fmtNum.format(s.factExits),
        ratio: (planExits != null && planExits > 0)
            ? s.factExits / planExits
            : null,
      ));
    }

    if (rows.isEmpty) return const SizedBox.shrink();

    // Алерты темпа расхода
    final alerts = s != null ? _buildAlerts(campaign, s) : <_PaceAlert>[];

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (alerts.isNotEmpty) ...[
            ...alerts.map((a) => _AlertBanner(alert: a)),
            const SizedBox(height: 10),
          ],
          // Header
          Row(
            children: [
              const Expanded(
                  child: Text('',
                      style:
                          TextStyle(color: kTextSecondary, fontSize: 11))),
              const SizedBox(
                width: 110,
                child: Text('ПЛАН',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                        color: kTextSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5)),
              ),
              const SizedBox(width: 12),
              const SizedBox(
                width: 110,
                child: Text('ФАКТ',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                        color: kAccent,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(height: 1, color: kBorder),
          const SizedBox(height: 4),
          ...rows.map((r) => Column(children: [r, const SizedBox(height: 4)])),
        ],
      ),
    );
  }
}

// ── Single plan/fact row ──────────────────────────────────────────────────────

class _PlanFactRow extends StatelessWidget {
  final String label;
  final String plan;
  final String? fact;
  final double? ratio; // fact / plan, 0..1+

  const _PlanFactRow({
    required this.label,
    required this.plan,
    required this.fact,
    required this.ratio,
  });

  Color get _barColor {
    if (ratio == null) return kAccent;
    if (ratio! > 0.85) return Colors.redAccent;
    if (ratio! > 0.5) return kAccent;
    return const Color(0xFF43A047); // green
  }

  @override
  Widget build(BuildContext context) {
    final pct = ratio != null
        ? '${(ratio! * 100).toStringAsFixed(0)}%'
        : null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Label
              Expanded(
                child: Text(label,
                    style: const TextStyle(
                        color: kTextPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w500)),
              ),
              // Plan value
              SizedBox(
                width: 110,
                child: Text(plan,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                        color: kTextSecondary, fontSize: 13)),
              ),
              const SizedBox(width: 12),
              // Fact value + percent
              SizedBox(
                width: 110,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (pct != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: _barColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(pct,
                            style: TextStyle(
                                color: _barColor,
                                fontSize: 11,
                                fontWeight: FontWeight.w600)),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Text(
                      fact ?? '—',
                      style: TextStyle(
                          color: fact != null ? kTextPrimary : kTextSecondary,
                          fontSize: 13,
                          fontWeight: fact != null
                              ? FontWeight.w600
                              : FontWeight.normal),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (ratio != null) ...[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: ratio!.clamp(0.0, 1.0),
                backgroundColor: const Color(0xFFEEEEEE),
                valueColor: AlwaysStoppedAnimation(_barColor),
                minHeight: 4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Chart card ────────────────────────────────────────────────────────────────

class _ChartCard extends StatelessWidget {
  final CampaignStats stats;
  const _ChartCard({required this.stats});

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Показы по дням',
              style: TextStyle(
                  color: kTextPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Row(
            children: [
              if (stats.factOts > 0)
                _SmallStat(
                    label: 'OTS факт',
                    value: NumberFormat.compact(locale: 'ru')
                        .format(stats.factOts)),
              if (stats.factOts > 0 && stats.cpm > 0)
                const SizedBox(width: 20),
              if (stats.cpm > 0)
                _SmallStat(
                    label: 'CPM',
                    value: NumberFormat.currency(
                            locale: 'ru_RU', symbol: '₽', decimalDigits: 0)
                        .format(stats.cpm)),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 160,
            child: StatsChart(daily: stats.daily),
          ),
        ],
      ),
    );
  }
}

class _SmallStat extends StatelessWidget {
  final String label;
  final String value;
  const _SmallStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style:
                  const TextStyle(color: kTextSecondary, fontSize: 11)),
          const SizedBox(height: 2),
          Text(value,
              style: const TextStyle(
                  color: kTextPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 16)),
        ],
      );
}

// ── Pace alerts ───────────────────────────────────────────────────────────────

enum _PaceType { over, under }

class _PaceAlert {
  final String metric;
  final _PaceType type;
  final double pct; // отклонение в %

  const _PaceAlert(this.metric, this.type, this.pct);
}

/// Вычисляет ожидаемую долю суточного расхода исходя из текущего времени.
/// Предполагаем активные часы кампании: 8:00–22:00 (14 ч).
double _expectedDayFraction() {
  final now = DateTime.now();
  const start = 8;
  const end = 22;
  const total = end - start; // 14 часов
  final elapsed = (now.hour + now.minute / 60 - start).clamp(0.0, total.toDouble());
  if (elapsed < 0.5) return 0; // слишком рано — не проверяем
  return elapsed / total;
}

List<_PaceAlert> _buildAlerts(Campaign campaign, CampaignStats s) {
  final alerts = <_PaceAlert>[];
  final dayFraction = _expectedDayFraction();
  if (dayFraction <= 0) return alerts;

  void check(String label, double plan, double fact) {
    if (plan <= 0 || fact <= 0) return;
    final expected = plan * dayFraction;
    final pace = fact / expected;
    if (pace > 1.25) {
      alerts.add(_PaceAlert(label, _PaceType.over, (pace - 1) * 100));
    } else if (pace < 0.7) {
      alerts.add(_PaceAlert(label, _PaceType.under, (1 - pace) * 100));
    }
  }

  // Используем часовые данные если есть, иначе суточные
  if (s.hourlyBudgetPlan > 0 && s.hourlyBudgetFact > 0) {
    final pace = s.hourlyBudgetFact / s.hourlyBudgetPlan;
    if (pace > 1.25) alerts.add(_PaceAlert('Бюджет/час', _PaceType.over, (pace - 1) * 100));
    if (pace < 0.7)  alerts.add(_PaceAlert('Бюджет/час', _PaceType.under, (1 - pace) * 100));
  } else {
    check('Бюджет', campaign.dailyBudget ?? 0, s.factDailyBudget);
  }

  if (s.hourlyOtsPlan > 0 && s.hourlyOtsFact > 0) {
    final pace = s.hourlyOtsFact / s.hourlyOtsPlan;
    if (pace > 1.25) alerts.add(_PaceAlert('OTS/час', _PaceType.over, (pace - 1) * 100));
    if (pace < 0.7)  alerts.add(_PaceAlert('OTS/час', _PaceType.under, (1 - pace) * 100));
  } else if (s.factOts > 0) {
    check('OTS', s.planOts, s.factOts);
  }

  if (s.hourlyExitsFact > 0) {
    final planHourlyExits = (campaign.exits ?? 0) / 14; // 14 активных часов
    if (planHourlyExits > 0) {
      final pace = s.hourlyExitsFact / planHourlyExits;
      if (pace > 1.25) alerts.add(_PaceAlert('Выходы/час', _PaceType.over, (pace - 1) * 100));
      if (pace < 0.7)  alerts.add(_PaceAlert('Выходы/час', _PaceType.under, (1 - pace) * 100));
    }
  }

  return alerts;
}

class _AlertBanner extends StatelessWidget {
  final _PaceAlert alert;
  const _AlertBanner({required this.alert});

  @override
  Widget build(BuildContext context) {
    final isOver = alert.type == _PaceType.over;
    final color = isOver ? const Color(0xFFC62828) : const Color(0xFF1565C0);
    final bg = isOver ? const Color(0xFFFFEBEE) : const Color(0xFFE3F2FD);
    final icon = isOver ? '⚡' : '📉';
    final label = isOver ? 'Перерасход' : 'Недотрата';

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Text(icon, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$label ${alert.metric}: ${alert.pct.toStringAsFixed(0)}% от ожидаемого темпа',
              style: TextStyle(
                  color: color, fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Shared ────────────────────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: child,
      );
}
