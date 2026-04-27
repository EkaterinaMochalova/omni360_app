import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../main.dart';
import '../models/campaign.dart';
import '../models/service_dashboard.dart';
import '../providers/service_dashboard_provider.dart';

class ServiceDashboardScreen extends ConsumerWidget {
  const ServiceDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(serviceDashboardProvider);
    final controller = ref.read(serviceDashboardProvider.notifier);
    final campaigns = state.campaigns.asData?.value ?? const <Campaign>[];
    final filteredCampaigns = ServiceDashboardController.filterCampaigns(
      campaigns,
      state.query,
      filters: state.filters,
    );

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: const Text(
          'Сервисный дашборд',
          style: TextStyle(
            color: kTextPrimary,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Фильтры',
            onPressed: () => _openFilters(context, state, controller),
            icon: const Icon(Icons.tune_rounded),
          ),
          IconButton(
            tooltip: 'Обновить',
            onPressed: controller.refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          _DashboardToolbar(
            query: state.query,
            onSetLast7Days: () {
              final now = DateTime.now();
              controller.setRange(now.subtract(const Duration(days: 7)), now);
            },
            onSetLast30Days: () {
              final now = DateTime.now();
              controller.setRange(now.subtract(const Duration(days: 30)), now);
            },
            onPickCustomRange: () => _pickCustomRange(context, controller),
          ),
          Expanded(
            child: state.summaries.when(
              loading: () => Center(
                child: SizedBox(
                  width: 360,
                  child: _LoadingProgressCard(
                    loaded: state.statsLoadedCampaigns,
                    total: state.statsTotalCampaigns,
                  ),
                ),
              ),
              error: (e, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Не удалось загрузить сервисный дашборд.\n$e',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: kTextSecondary),
                  ),
                ),
              ),
              data: (summaries) {
                final overallSummaries =
                    state.overallSummaries.asData?.value ??
                    const <ServiceDashboardCampaignSummary>[];
                final totals = _buildTotals(filteredCampaigns, summaries);
                final overallTotals = _buildTotals(campaigns, overallSummaries);
                final hasActiveFilters = _activeFilters(state.query).isNotEmpty;
                final sorted = [...summaries]
                  ..sort((a, b) => b.spent.compareTo(a.spent));

                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (state.isStatsLoading)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _LoadingProgressCard(
                          loaded: state.statsLoadedCampaigns,
                          total: state.statsTotalCampaigns,
                        ),
                      ),
                    if (_activeFilters(state.query).isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _activeFilters(
                            state.query,
                          ).map((label) => Chip(label: Text(label))).toList(),
                        ),
                      ),
                    _SectionCard(
                      title: 'План на месяц',
                      subtitle:
                          'Активные кампании + кампании, завершённые в текущем месяце. Учтён только бюджет в рамках месяца.',
                      child: state.monthlyPlan.when(
                        loading: () => const Text(
                          'Считаем план на месяц...',
                          style: TextStyle(color: kTextSecondary),
                        ),
                        error: (e, _) => Text(
                          'Не удалось посчитать план на месяц: $e',
                          style: const TextStyle(color: kTextSecondary),
                        ),
                        data: (monthly) => Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            _KpiCard(
                              label:
                                  'Итого план на ${DateFormat('LLLL', 'ru_RU').format(monthly.monthStart)}',
                              value: _money(monthly.totalBudget),
                            ),
                            _KpiCard(
                              label: 'Кампаний в расчёте',
                              value: _int(monthly.campaignCount),
                            ),
                            _KpiCard(
                              label: 'Активных',
                              value: _int(monthly.activeCampaignCount),
                            ),
                            _KpiCard(
                              label: 'Завершены в месяце',
                              value: _int(monthly.completedThisMonthCount),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _SectionCard(
                      title: 'KPI',
                      subtitle: hasActiveFilters
                          ? 'Факт рассчитан по выбранным фильтрам. Проценты показывают долю от всех кампаний за тот же период.'
                          : 'Агрегировано по ${filteredCampaigns.length} кампаниям за выбранный период',
                      child: Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          _KpiCard(
                            label: 'Потрачено (факт)',
                            value: _money(totals.totalSpent),
                            shareText: hasActiveFilters
                                ? _shareText(
                                    totals.totalSpent,
                                    overallTotals.totalSpent,
                                  )
                                : null,
                          ),
                          _KpiCard(
                            label: 'Средняя стоимость выхода',
                            value: _money(totals.avgCostPerExit),
                          ),
                          _KpiCard(
                            label: 'Средний OTS на выход',
                            value: totals.avgOtsPerExit.toStringAsFixed(2),
                          ),
                          _KpiCard(
                            label: 'Всего показов (факт)',
                            value: _int(totals.totalImpressions),
                            shareText: hasActiveFilters
                                ? _shareTextInt(
                                    totals.totalImpressions,
                                    overallTotals.totalImpressions,
                                  )
                                : null,
                          ),
                          _KpiCard(
                            label: 'Всего OTS (факт)',
                            value: _int(totals.totalOts),
                            shareText: hasActiveFilters
                                ? _shareTextInt(
                                    totals.totalOts,
                                    overallTotals.totalOts,
                                  )
                                : null,
                          ),
                          _KpiCard(
                            label: 'Кампаний',
                            value: _int(totals.campaignCount),
                          ),
                          _KpiCard(
                            label: 'Активных',
                            value: _int(totals.activeCampaignCount),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    _SectionCard(
                      title: 'Топ кампаний',
                      subtitle: 'По потраченному бюджету (факт) за период',
                      child: sorted.isEmpty
                          ? const Text(
                              'Нет данных по выбранным фильтрам.',
                              style: TextStyle(color: kTextSecondary),
                            )
                          : Column(
                              children: sorted.take(15).map((summary) {
                                Campaign? campaign;
                                for (final item in filteredCampaigns) {
                                  if (int.tryParse(item.id) ==
                                      summary.campaignId) {
                                    campaign = item;
                                    break;
                                  }
                                }
                                return _CampaignSummaryRow(
                                  summary: summary,
                                  campaign: campaign,
                                );
                              }).toList(),
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _openFilters(
    BuildContext context,
    ServiceDashboardState state,
    ServiceDashboardController controller,
  ) {
    final searchCtrl = TextEditingController(text: state.query.campaignSearch);
    final brands = Set<String>.from(state.query.brands);
    final advertisers = Set<String>.from(state.query.advertisers);
    final operators = Set<String>.from(state.query.operators);
    final cities = Set<String>.from(state.query.cities);
    final formats = Set<String>.from(state.query.formats);
    var operatorsSearch = '';

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
                    'Фильтры сервиса',
                    style: TextStyle(
                      color: kTextPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: searchCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Кампании',
                      hintText: 'Поиск по названию или ID кампании',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _MultiSelectSection(
                    title: 'Бренды',
                    options: state.filters.brands,
                    selected: brands,
                    onChanged: () => setModalState(() {}),
                  ),
                  _MultiSelectSection(
                    title: 'Рекламодатели',
                    options: state.filters.advertisers,
                    selected: advertisers,
                    onChanged: () => setModalState(() {}),
                  ),
                  _MultiSelectSection(
                    title: 'Операторы',
                    options: state.filters.operators,
                    selected: operators,
                    searchable: true,
                    searchQuery: operatorsSearch,
                    searchHint: 'Поиск подрядчика',
                    onSearchChanged: (value) {
                      operatorsSearch = value;
                      setModalState(() {});
                    },
                    onChanged: () => setModalState(() {}),
                  ),
                  _MultiSelectSection(
                    title: 'Города',
                    options: state.filters.cities,
                    selected: cities,
                    onChanged: () => setModalState(() {}),
                  ),
                  _MultiSelectSection(
                    title: 'Форматы',
                    options: state.filters.formats,
                    selected: formats,
                    onChanged: () => setModalState(() {}),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () async {
                          await controller.updateFilters(
                            campaignSearch: '',
                            brands: {},
                            advertisers: {},
                            operators: {},
                            cities: {},
                            formats: {},
                          );
                          if (context.mounted) Navigator.pop(context);
                        },
                        child: const Text('Сбросить'),
                      ),
                      const Spacer(),
                      FilledButton(
                        onPressed: () async {
                          await controller.updateFilters(
                            campaignSearch: searchCtrl.text,
                            brands: brands,
                            advertisers: advertisers,
                            operators: operators,
                            cities: cities,
                            formats: formats,
                          );
                          if (context.mounted) Navigator.pop(context);
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

  Future<void> _pickCustomRange(
    BuildContext context,
    ServiceDashboardController controller,
  ) async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
      initialDateRange: DateTimeRange(
        start: now.subtract(const Duration(days: 7)),
        end: now,
      ),
      helpText: 'Выбери период',
      saveText: 'Применить',
      cancelText: 'Отмена',
      fieldStartHintText: 'Начало',
      fieldEndHintText: 'Конец',
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(
              context,
            ).colorScheme.copyWith(primary: kAccent),
          ),
          child: child!,
        );
      },
    );

    if (picked == null || !context.mounted) return;

    final start = DateTime(
      picked.start.year,
      picked.start.month,
      picked.start.day,
    );
    final end = DateTime(
      picked.end.year,
      picked.end.month,
      picked.end.day,
      23,
      59,
      59,
    );
    final inclusiveDays = end.difference(start).inDays + 1;

    if (inclusiveDays > 31) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Период не должен превышать 31 день.')),
      );
      return;
    }

    await controller.setRange(start, end);
  }

  ServiceDashboardTotals _buildTotals(
    List<Campaign> campaigns,
    List<ServiceDashboardCampaignSummary> summaries,
  ) {
    final totalSpent = summaries.fold<double>(
      0,
      (sum, item) => sum + item.spent,
    );
    final totalImpressions = summaries.fold<int>(
      0,
      (sum, item) => sum + item.impressions,
    );
    final totalOts = summaries.fold<int>(0, (sum, item) => sum + item.ots);
    final avgCostPerExit = totalImpressions > 0
        ? totalSpent / totalImpressions
        : 0.0;
    final avgOtsPerExit = totalImpressions > 0
        ? totalOts / totalImpressions
        : 0.0;

    return ServiceDashboardTotals(
      campaignCount: campaigns.length,
      activeCampaignCount: campaigns
          .where((campaign) => campaign.isActive)
          .length,
      totalSpent: totalSpent,
      totalImpressions: totalImpressions,
      totalOts: totalOts,
      avgCostPerExit: avgCostPerExit,
      avgOtsPerExit: avgOtsPerExit,
    );
  }

  List<String> _activeFilters(ServiceDashboardQuery query) {
    final items = <String>[];
    if (query.campaignSearch.trim().isNotEmpty) {
      items.add('Кампании: ${query.campaignSearch.trim()}');
    }
    if (query.brands.isNotEmpty) {
      items.add(_formatFilterValues('Бренды', query.brands));
    }
    if (query.advertisers.isNotEmpty) {
      items.add(_formatFilterValues('Рекламодатели', query.advertisers));
    }
    if (query.operators.isNotEmpty) {
      items.add(_formatFilterValues('Операторы', query.operators));
    }
    if (query.cities.isNotEmpty) {
      items.add(_formatFilterValues('Города', query.cities));
    }
    if (query.formats.isNotEmpty) {
      items.add(_formatFilterValues('Форматы', query.formats));
    }
    return items;
  }

  String _formatFilterValues(String label, Set<String> values) {
    final sorted = values.toList()..sort();
    const previewLimit = 2;
    final preview = sorted.take(previewLimit).join(', ');
    final rest = sorted.length - previewLimit;
    final suffix = rest > 0 ? ' +$rest' : '';
    return '$label: $preview$suffix';
  }

  static String _money(double value) => NumberFormat.currency(
    locale: 'ru_RU',
    symbol: '₽',
    decimalDigits: value >= 1000 ? 0 : 2,
  ).format(value);

  static String _int(num value) =>
      NumberFormat.decimalPattern('ru_RU').format(value);

  static String? _shareText(double value, double total) {
    if (total <= 0) return null;
    final safeTotal = total < value ? value : total;
    final percent = ((value / safeTotal) * 100).clamp(0, 100).toDouble();
    return '${_formatPercent(percent)} от общего';
  }

  static String? _shareTextInt(int value, int total) {
    if (total <= 0) return null;
    final safeTotal = total < value ? value : total;
    final percent = ((value / safeTotal) * 100).clamp(0, 100).toDouble();
    return '${_formatPercent(percent)} от общего';
  }

  static String _formatPercent(double percent) {
    if (percent >= 10) return '${percent.toStringAsFixed(0)}%';
    if (percent >= 1) return '${percent.toStringAsFixed(1)}%';
    if (percent >= 0.1) return '${percent.toStringAsFixed(2)}%';
    return '${percent.toStringAsFixed(3)}%';
  }
}

class _DashboardToolbar extends StatelessWidget {
  final ServiceDashboardQuery query;
  final VoidCallback onSetLast7Days;
  final VoidCallback onSetLast30Days;
  final VoidCallback onPickCustomRange;

  const _DashboardToolbar({
    required this.query,
    required this.onSetLast7Days,
    required this.onSetLast30Days,
    required this.onPickCustomRange,
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
              _RangeChip(label: '7 дней', onTap: onSetLast7Days),
              const SizedBox(width: 8),
              _RangeChip(label: '30 дней', onTap: onSetLast30Days),
              const SizedBox(width: 8),
              _RangeChip(label: 'Выбрать даты', onTap: onPickCustomRange),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Период: ${dateFmt.format(query.start)} - ${dateFmt.format(query.end)}',
            style: const TextStyle(color: kTextSecondary, fontSize: 12),
          ),
        ],
      ),
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
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: kBg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: kBorder),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: kTextPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;

  const _SectionCard({required this.title, this.subtitle, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
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

class _KpiCard extends StatelessWidget {
  final String label;
  final String value;
  final String? shareText;

  const _KpiCard({required this.label, required this.value, this.shareText});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 150,
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
          if (shareText != null) ...[
            const SizedBox(height: 4),
            Text(
              shareText!,
              style: const TextStyle(
                color: kAccent,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _LoadingProgressCard extends StatelessWidget {
  const _LoadingProgressCard({required this.loaded, required this.total});

  final int loaded;
  final int total;

  @override
  Widget build(BuildContext context) {
    final value = total > 0 ? (loaded / total).clamp(0.0, 1.0) : null;
    final label = total > 0
        ? 'Загружаем данные: $loaded из $total кампаний'
        : 'Загружаем данные...';

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE6EAF3)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: kTextPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: value,
              minHeight: 6,
              backgroundColor: const Color(0xFFE8ECF5),
              color: kAccent,
              borderRadius: BorderRadius.circular(999),
            ),
          ],
        ),
      ),
    );
  }
}

class _CampaignSummaryRow extends StatelessWidget {
  final ServiceDashboardCampaignSummary summary;
  final Campaign? campaign;

  const _CampaignSummaryRow({required this.summary, required this.campaign});

  @override
  Widget build(BuildContext context) {
    final utilization = summary.budget > 0
        ? (summary.spent / summary.budget).clamp(0.0, 1.0)
        : 0.0;

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
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      summary.campaignName,
                      style: const TextStyle(
                        color: kTextPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'ID: ${summary.campaignId}',
                      style: const TextStyle(
                        color: kTextSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        if (campaign?.brandName != null) campaign!.brandName,
                        if (campaign?.customerName != null)
                          campaign!.customerName,
                        if (campaign != null &&
                            campaign!.displayOwners.isNotEmpty)
                          campaign!.displayOwners.join(', '),
                      ].whereType<String>().join(' • '),
                      style: const TextStyle(
                        color: kTextSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                ServiceDashboardScreen._money(summary.spent),
                style: const TextStyle(
                  color: kTextPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          LinearProgressIndicator(
            value: utilization,
            minHeight: 6,
            borderRadius: BorderRadius.circular(999),
            backgroundColor: const Color(0xFFECEFF4),
            valueColor: const AlwaysStoppedAnimation(kAccent),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 14,
            runSpacing: 8,
            children: [
              _MiniStat(
                label: 'Потрачено',
                value: ServiceDashboardScreen._money(summary.spent),
              ),
              _MiniStat(
                label: 'Показы',
                value: ServiceDashboardScreen._int(summary.impressions),
              ),
              _MiniStat(
                label: 'OTS',
                value: ServiceDashboardScreen._int(summary.ots),
              ),
              _MiniStat(
                label: 'CPM',
                value: ServiceDashboardScreen._money(summary.cpm),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;

  const _MiniStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: const TextStyle(fontSize: 12),
        children: [
          TextSpan(
            text: '$label: ',
            style: const TextStyle(color: kTextSecondary),
          ),
          TextSpan(
            text: value,
            style: const TextStyle(
              color: kTextPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _MultiSelectSection extends StatelessWidget {
  final String title;
  final List<String> options;
  final Set<String> selected;
  final bool searchable;
  final String searchQuery;
  final String? searchHint;
  final ValueChanged<String>? onSearchChanged;
  final VoidCallback onChanged;

  const _MultiSelectSection({
    required this.title,
    required this.options,
    required this.selected,
    this.searchable = false,
    this.searchQuery = '',
    this.searchHint,
    this.onSearchChanged,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (options.isEmpty) return const SizedBox.shrink();
    final normalizedQuery = searchQuery.trim().toLowerCase();
    final visibleOptions = normalizedQuery.isEmpty
        ? options
        : options
              .where((option) => option.toLowerCase().contains(normalizedQuery))
              .toList();

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: kTextPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (searchable) ...[
            const SizedBox(height: 8),
            TextField(
              onChanged: onSearchChanged,
              decoration: InputDecoration(
                hintText: searchHint ?? 'Поиск',
                prefixIcon: const Icon(Icons.search_rounded),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                border: const OutlineInputBorder(),
              ),
            ),
          ],
          const SizedBox(height: 8),
          if (visibleOptions.isEmpty)
            const Text(
              'Ничего не найдено',
              style: TextStyle(color: kTextSecondary, fontSize: 12),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: visibleOptions.map((option) {
                final isSelected = selected.contains(option);
                return FilterChip(
                  selected: isSelected,
                  label: Text(option),
                  onSelected: (value) {
                    if (value) {
                      selected.add(option);
                    } else {
                      selected.remove(option);
                    }
                    onChanged();
                  },
                );
              }).toList(),
            ),
        ],
      ),
    );
  }
}

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 4,
      decoration: BoxDecoration(
        color: const Color(0xFFD7DCE3),
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }
}
