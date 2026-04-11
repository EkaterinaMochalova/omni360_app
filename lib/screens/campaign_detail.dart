import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../main.dart';
import '../providers/campaigns_provider.dart';
import '../models/campaign.dart';
import '../widgets/stats_chart.dart';
import '../utils/pace_alerts.dart';

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
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: kTextPrimary,
            size: 18,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: detail.maybeWhen(
          data: (c) => Text(
            c.name,
            style: const TextStyle(
              color: kTextPrimary,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
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
          child: Text(
            'Ошибка: $e',
            style: const TextStyle(color: kTextSecondary),
          ),
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
              stats.maybeWhen(
                data: (s) => _DetailedStatsCard(campaign: campaign, stats: s),
                orElse: () =>
                    _DetailedStatsCard(campaign: campaign, stats: null),
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
            decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
          const Spacer(),
          if (campaign.type != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: kAccentLight,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                campaign.type!,
                style: const TextStyle(color: kAccent, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  static (String, Color, Color) _statusStyle(String status) => switch (status
      .toUpperCase()) {
    'RUNNING' ||
    'ACTIVE' => ('Активна', const Color(0xFFE8F5E9), const Color(0xFF2E7D32)),
    'PAUSED' => ('На паузе', const Color(0xFFFFF3E0), const Color(0xFFE65100)),
    'NEW' => ('Новая', const Color(0xFFE3F2FD), const Color(0xFF1565C0)),
    'OFF_SCHEDULE' => (
      'Не в графике',
      const Color(0xFFFFFDE7),
      const Color(0xFFF9A825),
    ),
    'BUDGET_EXHAUSTED' || 'STOPPED' => (
      'Бюджет исчерпан',
      const Color(0xFFFFEBEE),
      const Color(0xFFC62828),
    ),
    'COMPLETED' => (
      'Завершена',
      const Color(0xFFF5F5F5),
      const Color(0xFF757575),
    ),
    _ => (
      status.isNotEmpty ? status : 'Неизвестно',
      const Color(0xFFF5F5F5),
      const Color(0xFF757575),
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
          const Icon(
            Icons.calendar_today_outlined,
            size: 16,
            color: kTextSecondary,
          ),
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
      locale: 'ru_RU',
      symbol: '₽',
      decimalDigits: 0,
    );
    final fmtNum = NumberFormat.decimalPattern('ru_RU');

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
      rows.add(
        _PlanFactRow(
          label: 'Бюджет',
          plan: fmtRub.format(planBudget),
          fact: factBudget != null ? fmtRub.format(factBudget) : null,
          ratio: factBudget != null ? factBudget / planBudget : null,
        ),
      );
    }

    // В день
    if (planDaily != null && planDaily > 0) {
      final factDaily = (s != null && s.factDailyBudget > 0)
          ? s.factDailyBudget
          : null;
      rows.add(
        _PlanFactRow(
          label: 'В день',
          plan: fmtRub.format(planDaily),
          fact: factDaily != null ? fmtRub.format(factDaily) : null,
          ratio: factDaily != null ? factDaily / planDaily : null,
        ),
      );
    }

    // OTS — показываем если есть план ИЛИ факт
    final factOts = (s != null && s.factOts > 0) ? s.factOts : null;
    if ((planOts != null && planOts > 0) || factOts != null) {
      rows.add(
        _PlanFactRow(
          label: 'OTS',
          plan: (planOts != null && planOts > 0) ? fmtNum.format(planOts) : '—',
          fact: factOts != null ? fmtNum.format(factOts) : null,
          ratio: (factOts != null && planOts != null && planOts > 0)
              ? factOts / planOts
              : null,
        ),
      );
    }

    // Выходы (totalCountShowed)
    if (s != null && s.factExits > 0) {
      final planExits = campaign.exits;
      rows.add(
        _PlanFactRow(
          label: 'Выходы',
          plan: planExits != null && planExits > 0
              ? fmtNum.format(planExits)
              : '—',
          fact: fmtNum.format(s.factExits),
          ratio: (planExits != null && planExits > 0)
              ? s.factExits / planExits
              : null,
        ),
      );
    }

    if (rows.isEmpty) return const SizedBox.shrink();

    // Алерты темпа расхода
    final alerts = s != null ? buildAlerts(campaign, s) : <PaceAlert>[];

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
                child: Text(
                  '',
                  style: TextStyle(color: kTextSecondary, fontSize: 11),
                ),
              ),
              const SizedBox(
                width: 110,
                child: Text(
                  'ПЛАН',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: kTextSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              const SizedBox(
                width: 110,
                child: Text(
                  'ФАКТ',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: kAccent,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
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
    final pct = ratio != null ? '${(ratio! * 100).toStringAsFixed(0)}%' : null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Label
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: kTextPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              // Plan value
              SizedBox(
                width: 110,
                child: Text(
                  plan,
                  textAlign: TextAlign.right,
                  style: const TextStyle(color: kTextSecondary, fontSize: 13),
                ),
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
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: _barColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          pct,
                          style: TextStyle(
                            color: _barColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
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
                            : FontWeight.normal,
                      ),
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

// ── Detailed stats card ───────────────────────────────────────────────────────

class _DetailedStatsCard extends StatelessWidget {
  final Campaign campaign;
  final CampaignStats? stats;

  const _DetailedStatsCard({required this.campaign, required this.stats});

  @override
  Widget build(BuildContext context) {
    final fmtRub = NumberFormat.currency(
      locale: 'ru_RU',
      symbol: '₽',
      decimalDigits: 0,
    );
    final fmtNum = NumberFormat.decimalPattern('ru_RU');
    final s = stats;

    String rub(double? value) =>
        value != null && value > 0 ? fmtRub.format(value) : '—';
    String num(double? value) =>
        value != null && value > 0 ? fmtNum.format(value) : '—';
    String intNum(int? value) =>
        value != null && value > 0 ? fmtNum.format(value) : '—';

    final planHourlyExits = ((campaign.exits ?? 0) > 0)
        ? (campaign.exits! / 14)
        : null;

    final rows = <_DetailedStatRowData>[
      _DetailedStatRowData(
        label: 'Бюджет общий',
        plan: rub(campaign.budget),
        fact: rub(s?.factBudget),
        ratio: _ratio(campaign.budget, s?.factBudget),
      ),
      _DetailedStatRowData(
        label: 'Бюджет в день',
        plan: rub(campaign.dailyBudget),
        fact: rub(s?.factDailyBudget),
        ratio: _ratio(campaign.dailyBudget, s?.factDailyBudget),
      ),
      _DetailedStatRowData(
        label: 'Бюджет в час',
        plan: rub(s?.hourlyBudgetPlan),
        fact: rub(s?.hourlyBudgetFact),
        ratio: _ratio(s?.hourlyBudgetPlan, s?.hourlyBudgetFact),
      ),
      _DetailedStatRowData(
        label: 'OTS общий',
        plan: num(campaign.ots),
        fact: num(s?.factOts),
        ratio: _ratio(campaign.ots, s?.factOts),
      ),
      _DetailedStatRowData(
        label: 'OTS в час',
        plan: num(s?.hourlyOtsPlan),
        fact: num(s?.hourlyOtsFact),
        ratio: _ratio(s?.hourlyOtsPlan, s?.hourlyOtsFact),
      ),
      _DetailedStatRowData(
        label: 'Выходы общие',
        plan: num(campaign.exits),
        fact: intNum(s?.factExits),
        ratio: _ratio(campaign.exits, s?.factExits.toDouble()),
      ),
      _DetailedStatRowData(
        label: 'Выходы в час',
        plan: num(planHourlyExits),
        fact: intNum(s?.hourlyExitsFact),
        ratio: _ratio(planHourlyExits, s?.hourlyExitsFact.toDouble()),
      ),
      _DetailedStatRowData(
        label: 'CPM',
        plan: '—',
        fact: rub(s?.cpm),
        ratio: null,
      ),
    ].where((row) => row.plan != '—' || row.fact != '—').toList();

    if (rows.isEmpty) return const SizedBox.shrink();

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Подробная статистика',
            style: TextStyle(
              color: kTextPrimary,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Построчно по ключевым метрикам кампании',
            style: TextStyle(color: kTextSecondary, fontSize: 12),
          ),
          const SizedBox(height: 14),
          Row(
            children: const [
              Expanded(
                child: Text(
                  'Метрика',
                  style: TextStyle(
                    color: kTextSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              SizedBox(
                width: 96,
                child: Text(
                  'ПЛАН',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: kTextSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              SizedBox(width: 12),
              SizedBox(
                width: 96,
                child: Text(
                  'ФАКТ',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: kAccent,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Divider(height: 1, color: kBorder),
          const SizedBox(height: 4),
          ...rows.map((row) => _DetailedStatRow(row: row)),
        ],
      ),
    );
  }

  static double? _ratio(double? plan, double? fact) {
    if (plan == null || fact == null || plan <= 0 || fact <= 0) return null;
    return fact / plan;
  }
}

class _DetailedStatRowData {
  final String label;
  final String plan;
  final String fact;
  final double? ratio;

  const _DetailedStatRowData({
    required this.label,
    required this.plan,
    required this.fact,
    required this.ratio,
  });
}

class _DetailedStatRow extends StatelessWidget {
  final _DetailedStatRowData row;

  const _DetailedStatRow({required this.row});

  @override
  Widget build(BuildContext context) {
    final delta = row.ratio == null
        ? null
        : '${row.ratio! >= 1 ? '+' : ''}${((row.ratio! - 1) * 100).toStringAsFixed(0)}%';
    final deltaColor = row.ratio == null
        ? kTextSecondary
        : row.ratio! > 1.05
        ? const Color(0xFFC62828)
        : row.ratio! < 0.95
        ? const Color(0xFF1565C0)
        : const Color(0xFF2E7D32);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  row.label,
                  style: const TextStyle(
                    color: kTextPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              SizedBox(
                width: 96,
                child: Text(
                  row.plan,
                  textAlign: TextAlign.right,
                  style: const TextStyle(color: kTextSecondary, fontSize: 13),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 96,
                child: Text(
                  row.fact,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    color: kTextPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (delta != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: deltaColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    delta,
                    style: TextStyle(
                      color: deltaColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          const Divider(height: 1, color: kBorder),
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
          const Text(
            'Показы по дням',
            style: TextStyle(
              color: kTextPrimary,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              if (stats.factOts > 0)
                _SmallStat(
                  label: 'OTS факт',
                  value: NumberFormat.compact(
                    locale: 'ru',
                  ).format(stats.factOts),
                ),
              if (stats.factOts > 0 && stats.cpm > 0) const SizedBox(width: 20),
              if (stats.cpm > 0)
                _SmallStat(
                  label: 'CPM',
                  value: NumberFormat.currency(
                    locale: 'ru_RU',
                    symbol: '₽',
                    decimalDigits: 0,
                  ).format(stats.cpm),
                ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(height: 160, child: StatsChart(daily: stats.daily)),
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
      Text(label, style: const TextStyle(color: kTextSecondary, fontSize: 11)),
      const SizedBox(height: 2),
      Text(
        value,
        style: const TextStyle(
          color: kTextPrimary,
          fontWeight: FontWeight.bold,
          fontSize: 16,
        ),
      ),
    ],
  );
}

// ── Pace alert banner ─────────────────────────────────────────────────────────

class _AlertBanner extends StatelessWidget {
  final PaceAlert alert;
  const _AlertBanner({required this.alert});

  @override
  Widget build(BuildContext context) {
    final isNoExits = alert.type == PaceType.noExits;
    final isOver = alert.type == PaceType.over;
    final color = isNoExits
        ? const Color(0xFFE65100)
        : isOver
        ? const Color(0xFFC62828)
        : const Color(0xFF1565C0);
    final bg = isNoExits
        ? const Color(0xFFFFF3E0)
        : isOver
        ? const Color(0xFFFFEBEE)
        : const Color(0xFFE3F2FD);
    final icon = isNoExits
        ? '⚠️'
        : isOver
        ? '⚡'
        : '📉';
    final text = isNoExits
        ? 'Нет выходов за последний час'
        : '${isOver ? 'Перерасход' : 'Недотрата'} ${alert.metric}: ${alert.pct.toStringAsFixed(0)}% от ожидаемого темпа';

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
              text,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
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
