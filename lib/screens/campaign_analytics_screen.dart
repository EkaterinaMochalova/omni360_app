import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../main.dart';
import '../models/campaign_analytics.dart';
import '../providers/campaign_analytics_provider.dart';

class CampaignAnalyticsScreen extends ConsumerWidget {
  final String campaignId;
  final String campaignName;

  const CampaignAnalyticsScreen({
    super.key,
    required this.campaignId,
    required this.campaignName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(campaignAnalyticsProvider(campaignId));
    final controller = ref.read(campaignAnalyticsProvider(campaignId).notifier);

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Аукционная аналитика',
              style: TextStyle(
                color: kTextPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            Text(
              campaignName,
              style: const TextStyle(color: kTextSecondary, fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Настроить дашборд',
            onPressed: () => _openDashboardSettings(context, state, controller),
            icon: const Icon(Icons.dashboard_customize_outlined),
          ),
          IconButton(
            tooltip: 'Фильтры',
            onPressed: () => _openFilters(context, state, controller),
            icon: const Icon(Icons.tune_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          _Toolbar(
            state: state,
            onSetLast24Hours: () {
              final now = DateTime.now();
              controller.setRange(now.subtract(const Duration(hours: 24)), now);
            },
            onSetLast7Days: () {
              final now = DateTime.now();
              controller.setRange(now.subtract(const Duration(days: 7)), now);
            },
            onRefresh: controller.fetchImpressions,
          ),
          Expanded(
            child: state.impressions.when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: kAccent),
              ),
              error: (e, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    _buildErrorMessage(e),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: kTextSecondary),
                  ),
                ),
              ),
              data: (page) => _AnalyticsBody(
                state: state,
                page: page,
                aggregate:
                    state.aggregate.asData?.value ??
                    CampaignAnalyticsAggregate.empty(),
                onPageChange: controller.setPage,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openDashboardSettings(
    BuildContext context,
    CampaignAnalyticsState state,
    CampaignAnalyticsController controller,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _SheetHandle(),
              const SizedBox(height: 16),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Настройка дашборда',
                  style: TextStyle(
                    color: kTextPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              _DashboardToggleTile(
                title: 'Сводка',
                value: state.prefs.showSummary,
                onChanged: (value) => controller.updatePrefs(
                  state.prefs.copyWith(showSummary: value),
                ),
              ),
              _DashboardToggleTile(
                title: 'Разбивка по статусам',
                value: state.prefs.showStateBreakdown,
                onChanged: (value) => controller.updatePrefs(
                  state.prefs.copyWith(showStateBreakdown: value),
                ),
              ),
              _DashboardToggleTile(
                title: 'Причины проигрышей',
                value: state.prefs.showFailureBreakdown,
                onChanged: (value) => controller.updatePrefs(
                  state.prefs.copyWith(showFailureBreakdown: value),
                ),
              ),
              _DashboardToggleTile(
                title: 'Список запросов',
                value: state.prefs.showRequestTable,
                onChanged: (value) => controller.updatePrefs(
                  state.prefs.copyWith(showRequestTable: value),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openFilters(
    BuildContext context,
    CampaignAnalyticsState state,
    CampaignAnalyticsController controller,
  ) {
    final filters = state.filters.asData?.value;
    if (filters == null) return;

    final selectedStates = Set<String>.from(state.query.states);
    final selectedReasons = Set<String>.from(state.query.failureReasons);
    final addressCtrl = TextEditingController(text: state.query.address);
    final gidCtrl = TextEditingController(text: state.query.inventoryGid);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: StatefulBuilder(
            builder: (context, setModalState) => SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Center(child: _SheetHandle()),
                  const SizedBox(height: 16),
                  const Text(
                    'Фильтры запросов',
                    style: TextStyle(
                      color: kTextPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Экран',
                    style: TextStyle(
                      color: kTextPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: addressCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Адрес',
                      hintText: 'Например: Ленинский пр-т, дом 31',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: gidCtrl,
                    decoration: const InputDecoration(
                      labelText: 'GID экрана',
                      hintText: 'Например: 2006-04-10-...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Статусы',
                    style: TextStyle(
                      color: kTextPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: filters.states.entries.map((entry) {
                      final selected = selectedStates.contains(entry.key);
                      return FilterChip(
                        selected: selected,
                        label: Text(entry.value),
                        onSelected: (value) {
                          setModalState(() {
                            if (value) {
                              selectedStates.add(entry.key);
                            } else {
                              selectedStates.remove(entry.key);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Причины проигрышей',
                    style: TextStyle(
                      color: kTextPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: filters.failureReasons.entries.map((entry) {
                      final selected = selectedReasons.contains(entry.key);
                      return FilterChip(
                        selected: selected,
                        label: Text(entry.value),
                        onSelected: (value) {
                          setModalState(() {
                            if (value) {
                              selectedReasons.add(entry.key);
                            } else {
                              selectedReasons.remove(entry.key);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () {
                          selectedStates.clear();
                          selectedReasons.clear();
                          controller.setStates({});
                          controller.setFailureReasons({});
                          controller.setScreenFilters(
                            address: '',
                            inventoryGid: '',
                          );
                          Navigator.pop(context);
                        },
                        child: const Text('Сбросить'),
                      ),
                      const Spacer(),
                      FilledButton(
                        onPressed: () async {
                          await controller.setScreenFilters(
                            address: addressCtrl.text,
                            inventoryGid: gidCtrl.text,
                          );
                          await controller.setStates(selectedStates);
                          await controller.setFailureReasons(selectedReasons);
                          if (context.mounted) {
                            Navigator.pop(context);
                          }
                        },
                        style: FilledButton.styleFrom(backgroundColor: kAccent),
                        child: const Text('Применить'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _buildErrorMessage(Object error) {
    final base = 'Не удалось загрузить аукционную аналитику.';
    if (kIsWeb && Uri.base.host.endsWith('github.io')) {
      return '$base\n\nДля web-версии на GitHub Pages backend OmniBoard блокирует часть запросов CORS-ограничениями. Открой Netlify deploy, где запросы идут через proxy.';
    }
    return '$base\n$error';
  }
}

class _Toolbar extends StatelessWidget {
  final CampaignAnalyticsState state;
  final VoidCallback onSetLast24Hours;
  final VoidCallback onSetLast7Days;
  final VoidCallback onRefresh;

  const _Toolbar({
    required this.state,
    required this.onSetLast24Hours,
    required this.onSetLast7Days,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('dd.MM HH:mm');
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _RangeChip(label: '24 часа', onTap: onSetLast24Hours),
              const SizedBox(width: 8),
              _RangeChip(label: '7 дней', onTap: onSetLast7Days),
              const Spacer(),
              IconButton(
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh_rounded, color: kTextSecondary),
                tooltip: 'Обновить',
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Период: ${dateFmt.format(state.query.start)} - ${dateFmt.format(state.query.end)}',
            style: const TextStyle(color: kTextSecondary, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _AnalyticsBody extends StatelessWidget {
  final CampaignAnalyticsState state;
  final CampaignImpressionsPage page;
  final CampaignAnalyticsAggregate aggregate;
  final ValueChanged<int> onPageChange;

  const _AnalyticsBody({
    required this.state,
    required this.page,
    required this.aggregate,
    required this.onPageChange,
  });

  @override
  Widget build(BuildContext context) {
    final records = page.content;
    final stateCounts = aggregate.stateCounts;
    final failureCounts = aggregate.failureCounts;
    final wins = aggregate.wins;
    final losses = aggregate.losses;
    final successes = aggregate.successes;
    final lossRate =
        aggregate.totalRequests == 0 ? 0.0 : losses / aggregate.totalRequests;
    final hasScreenFilter =
        state.query.address.isNotEmpty || state.query.inventoryGid.isNotEmpty;
    final selectedScreenLabel = [
      if (state.query.address.isNotEmpty) state.query.address,
      if (state.query.inventoryGid.isNotEmpty)
        'GID: ${state.query.inventoryGid}',
    ].join(' • ');

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (state.prefs.showSummary)
          _CardSection(
            title: 'Сводка',
            subtitle: hasScreenFilter ? selectedScreenLabel : null,
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _MetricCard(label: 'Запросов', value: '${aggregate.totalRequests}'),
                _MetricCard(label: 'Победы', value: '$wins'),
                _MetricCard(label: 'Проигрыши', value: '$losses'),
                if (hasScreenFilter)
                  _MetricCard(
                    label: 'Процент проигрышей',
                    value: '${(lossRate * 100).toStringAsFixed(1)}%',
                  ),
                _MetricCard(label: 'Успешные показы', value: '$successes'),
              ],
            ),
          ),
        if (state.prefs.showSummary) const SizedBox(height: 12),
        if (state.prefs.showStateBreakdown)
          _CardSection(
            title: 'Статусы запросов',
            child: Column(
              children: stateCounts.entries
                  .map(
                    (entry) => _BreakdownRow(
                      label: entry.key,
                      value: entry.value,
                      total: aggregate.totalRequests,
                    ),
                  )
                  .toList(),
            ),
          ),
        if (state.prefs.showStateBreakdown) const SizedBox(height: 12),
        if (state.prefs.showFailureBreakdown && failureCounts.isNotEmpty)
          _CardSection(
            title: 'Причины проигрышей',
            child: Column(
              children: failureCounts.entries
                  .map(
                    (entry) => _BreakdownRow(
                      label: entry.key,
                      value: entry.value,
                      total: aggregate.totalRequests,
                    ),
                  )
                  .toList(),
            ),
          ),
        if (state.prefs.showFailureBreakdown && failureCounts.isNotEmpty)
          const SizedBox(height: 12),
        if (state.prefs.showRequestTable)
          _CardSection(
            title: 'Каждый запрос',
            subtitle:
                'Победы, проигрыши и аукционные параметры по каждому request',
            child: records.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'По выбранным фильтрам запросов не найдено.',
                      style: TextStyle(color: kTextSecondary),
                    ),
                  )
                : Column(
                    children: [
                      ...records.map((record) => _RequestRow(record: record)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          OutlinedButton(
                            onPressed: page.page > 0
                                ? () => onPageChange(page.page - 1)
                                : null,
                            child: const Text('Назад'),
                          ),
                          const Spacer(),
                          Text(
                            'Страница ${page.page + 1} из ${page.totalPages}',
                            style: const TextStyle(
                              color: kTextSecondary,
                              fontSize: 12,
                            ),
                          ),
                          const Spacer(),
                          OutlinedButton(
                            onPressed: !page.last
                                ? () => onPageChange(page.page + 1)
                                : null,
                            child: const Text('Вперёд'),
                          ),
                        ],
                      ),
                    ],
                  ),
          ),
      ],
    );
  }
}

class _CardSection extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;

  const _CardSection({required this.title, this.subtitle, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: kTextPrimary,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              style: const TextStyle(color: kTextSecondary, fontSize: 12),
            ),
          ],
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;

  const _MetricCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 145,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kBg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: kTextSecondary, fontSize: 12),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: kTextPrimary,
              fontWeight: FontWeight.bold,
              fontSize: 20,
            ),
          ),
        ],
      ),
    );
  }
}

class _BreakdownRow extends StatelessWidget {
  final String label;
  final int value;
  final int total;

  const _BreakdownRow({
    required this.label,
    required this.value,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    final ratio = total > 0 ? value / total : 0.0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: kTextPrimary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Text(
                '$value',
                style: const TextStyle(
                  color: kTextPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          LinearProgressIndicator(
            value: ratio.clamp(0.0, 1.0),
            minHeight: 6,
            borderRadius: BorderRadius.circular(999),
            backgroundColor: const Color(0xFFECEFF4),
            valueColor: const AlwaysStoppedAnimation(kAccent),
          ),
        ],
      ),
    );
  }
}

class _RequestRow extends StatelessWidget {
  final CampaignImpressionRecord record;

  const _RequestRow({required this.record});

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat.currency(
      locale: 'ru_RU',
      symbol: '₽',
      decimalDigits: 2,
    );
    final statusColor = switch (record.state) {
      'WIN' || 'SUCCESS' => const Color(0xFF2E7D32),
      'FAILED' => const Color(0xFFC62828),
      'SENT' => const Color(0xFF1565C0),
      _ => kTextSecondary,
    };

    String money(double? value) => value == null ? '—' : fmt.format(value);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kBg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      record.reqId ?? record.id,
                      style: const TextStyle(
                        color: kTextPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        if (record.city != null && record.city!.isNotEmpty)
                          record.city,
                        if (record.inventoryName != null &&
                            record.inventoryName!.isNotEmpty)
                          record.inventoryName,
                      ].join(' • '),
                      style: const TextStyle(
                        color: kTextSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  record.state,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 14,
            runSpacing: 8,
            children: [
              _RequestMetric(label: 'Bid', value: money(record.bid)),
              _RequestMetric(label: 'Bid floor', value: money(record.bidFloor)),
              _RequestMetric(label: 'Price', value: money(record.price)),
              _RequestMetric(
                label: 'Charged',
                value: money(record.chargedPrice),
              ),
            ],
          ),
          if (record.failureReasonType != null ||
              record.failureReasonCodeName != null ||
              record.failureReasonMessage != null) ...[
            const SizedBox(height: 10),
            Text(
              [
                    record.failureReasonType,
                    record.failureReasonCodeName,
                    record.failureReasonMessage,
                  ]
                  .whereType<String>()
                  .where((item) => item.isNotEmpty)
                  .join(' • '),
              style: const TextStyle(
                color: Color(0xFFC62828),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          if (record.showTime != null) ...[
            const SizedBox(height: 8),
            Text(
              DateFormat('dd.MM.yyyy HH:mm:ss').format(record.showTime!),
              style: const TextStyle(color: kTextSecondary, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

class _RequestMetric extends StatelessWidget {
  final String label;
  final String value;

  const _RequestMetric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: kTextSecondary, fontSize: 11),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            color: kTextPrimary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _DashboardToggleTile extends StatelessWidget {
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _DashboardToggleTile({
    required this.title,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      value: value,
      activeThumbColor: kAccent,
      activeTrackColor: kAccent.withValues(alpha: 0.35),
      onChanged: onChanged,
    );
  }
}

class _RangeChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _RangeChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: kBg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: kBorder),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: kTextPrimary,
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 4,
      decoration: BoxDecoration(
        color: kBorder,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}
