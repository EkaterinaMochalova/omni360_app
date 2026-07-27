import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../main.dart';
import '../models/campaign.dart';
import '../providers/campaigns_provider.dart';
import '../screens/campaign_detail.dart';

/// Быстрая слайд-панель с саммари по кампании (открывается по клику на
/// карточку в списке) + кнопка перехода на полную карточку кампании —
/// сохраняет весь существующий функционал (план/факт, подробная статистика,
/// график, аукционная аналитика), просто добавляя быстрый предпросмотр перед
/// ним.
class CampaignSummaryPanelOverlay extends ConsumerWidget {
  final Campaign campaign;
  final VoidCallback onClose;

  const CampaignSummaryPanelOverlay({
    super.key,
    required this.campaign,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fmt = NumberFormat.currency(
      locale: 'ru_RU',
      symbol: '₽',
      decimalDigits: 0,
    );
    final stats = ref
        .watch(campaignStatsProvider(campaign.id))
        .whenOrNull(data: (s) => s);
    final photoCoverage = ref.watch(campaignPhotoCoverageProvider(campaign.id));

    final effectiveSpent = (campaign.spent != null && campaign.spent! > 0)
        ? campaign.spent
        : (stats != null && stats.factBudget > 0 ? stats.factBudget : null);
    final ratio =
        (effectiveSpent != null && campaign.budget != null && campaign.budget! > 0)
        ? (effectiveSpent / campaign.budget!).clamp(0.0, 1.0)
        : null;
    final (statusBg, statusFg) = _statusColors(campaign.status);

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: onClose,
            child: Container(color: Colors.black.withValues(alpha: 0.25)),
          ),
        ),
        Positioned(
          top: 0,
          right: 0,
          bottom: 0,
          width: 380,
          child: Material(
            elevation: 8,
            color: Colors.white,
            child: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            campaign.name,
                            style: const TextStyle(
                              color: kTextPrimary,
                              fontWeight: FontWeight.bold,
                              fontSize: 17,
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: onClose,
                          child: const Icon(
                            Icons.close_rounded,
                            color: kTextSecondary,
                            size: 20,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'ID: ${campaign.id}${campaign.advertiser != null ? ' · ${campaign.advertiser}' : ''}',
                      style: const TextStyle(color: kTextSecondary, fontSize: 12),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: statusBg,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        campaign.displayStatus,
                        style: TextStyle(
                          color: statusFg,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 14,
                      crossAxisSpacing: 14,
                      childAspectRatio: 2.6,
                      children: [
                        _Stat(
                          'Бюджет',
                          campaign.budget != null ? fmt.format(campaign.budget) : '—',
                        ),
                        _Stat(
                          'Потрачено',
                          effectiveSpent != null ? fmt.format(effectiveSpent) : '—',
                        ),
                        _Stat(
                          'Осталось',
                          campaign.budget != null
                              ? fmt.format(
                                  ((campaign.budget ?? 0) - (effectiveSpent ?? 0))
                                      .clamp(0.0, double.infinity),
                                )
                              : '—',
                        ),
                        _Stat(
                          'Период',
                          '${campaign.startDate ?? '—'} – ${campaign.endDate ?? '—'}',
                        ),
                        _Stat(
                          'OTS',
                          campaign.ots != null
                              ? NumberFormat.compact(locale: 'ru').format(campaign.ots)
                              : '—',
                        ),
                        _Stat(
                          'Выходы',
                          campaign.exits != null
                              ? NumberFormat.compact(locale: 'ru').format(campaign.exits)
                              : '—',
                        ),
                        _Stat(
                          'Фотоотчёты',
                          photoCoverage.maybeWhen(
                            data: (c) => '${c.percent.toStringAsFixed(1)}%',
                            orElse: () => '—',
                          ),
                        ),
                      ],
                    ),
                    if (ratio != null) ...[
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: ratio,
                          backgroundColor: const Color(0xFFE8EAF6),
                          valueColor: AlwaysStoppedAnimation(
                            ratio > 0.85 ? Colors.redAccent : kAccent,
                          ),
                          minHeight: 6,
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () {
                          onClose();
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  CampaignDetailScreen(campaignId: campaign.id),
                            ),
                          );
                        },
                        style: FilledButton.styleFrom(backgroundColor: kAccent),
                        icon: const Icon(Icons.open_in_full_rounded, size: 16),
                        label: const Text('Открыть полную карточку'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  static (Color, Color) _statusColors(String status) {
    return switch (status.toUpperCase()) {
      'RUNNING' ||
      'ACTIVE' => (const Color(0xFFE8F5E9), const Color(0xFF2E7D32)),
      'PAUSED' => (const Color(0xFFFFF3E0), const Color(0xFFE65100)),
      'NEW' => (const Color(0xFFE3F2FD), const Color(0xFF1565C0)),
      'OFF_SCHEDULE' => (const Color(0xFFFFFDE7), const Color(0xFFF9A825)),
      'COMPLETED' => (const Color(0xFFF5F5F5), const Color(0xFF757575)),
      'BUDGET_EXHAUSTED' ||
      'STOPPED' => (const Color(0xFFFFEBEE), const Color(0xFFC62828)),
      _ => (const Color(0xFFF5F5F5), const Color(0xFF757575)),
    };
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;

  const _Stat(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: const TextStyle(color: kTextSecondary, fontSize: 11)),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            color: kTextPrimary,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
