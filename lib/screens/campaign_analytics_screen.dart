import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../main.dart';
import '../models/campaign_analytics.dart';
import '../models/loss_report.dart';
import '../providers/campaign_analytics_provider.dart';
import '../services/excel_export_service.dart';
import '../services/file_saver.dart';
import '../services/file_saver_stub.dart'
    if (dart.library.io) '../services/file_saver_native.dart'
    if (dart.library.html) '../services/file_saver_web.dart';
import '../services/local_order_store.dart';
import '../widgets/card_section.dart';
import '../widgets/loss_report_sections.dart';
import '../widgets/reorderable_flex_wrap.dart';

// Экран аукционной аналитики схлопнут с карточкой кампании в единый
// дашборд. Отсюда он берёт действия шапки, панель периода и сетку блоков.

Future<void> exportAnalyticsToExcel(
    BuildContext context,
    CampaignAnalyticsState state,
    String campaignName,
  ) async {
    final records = state.allRecords.asData?.value ?? const [];
    if (records.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Нет данных для экспорта за выбранный период')),
      );
      return;
    }

    try {
      final report = LossReportBuilder.build(records);
      final bytes = buildLossReportWorkbook(
        campaignName: campaignName,
        records: records,
        report: report,
      );
      final safeName = campaignName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final FileSaver saver = createFileSaver();
      await saver.saveAndShareFile(bytes, '$safeName-показы.xlsx');
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось сформировать отчёт: $e')),
      );
    }
  }

void openDashboardSettings(
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
              _DashboardToggleTile(
                title: 'Сводная по дням',
                value: state.prefs.showDailyBreakdown,
                onChanged: (value) => controller.updatePrefs(
                  state.prefs.copyWith(showDailyBreakdown: value),
                ),
              ),
              _DashboardToggleTile(
                title: 'Поднять ставки',
                value: state.prefs.showBidReport,
                onChanged: (value) => controller.updatePrefs(
                  state.prefs.copyWith(showBidReport: value),
                ),
              ),
              _DashboardToggleTile(
                title: 'К оператору',
                value: state.prefs.showOperatorReport,
                onChanged: (value) => controller.updatePrefs(
                  state.prefs.copyWith(showOperatorReport: value),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

void openAnalyticsFilters(
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

String analyticsErrorMessage(Object error) {
    final base = 'Не удалось загрузить аукционную аналитику.';
    if (kIsWeb && Uri.base.host.endsWith('github.io')) {
      return '$base\n\nДля web-версии на GitHub Pages backend OmniBoard блокирует часть запросов CORS-ограничениями. Открой Netlify deploy, где запросы идут через proxy.';
    }
    return '$base\n$error';
}

class AnalyticsToolbar extends StatelessWidget {
  final CampaignAnalyticsState state;
  final VoidCallback onSetLast24Hours;
  final VoidCallback onSetLast7Days;

  /// null — даты кампании неизвестны, и брать «весь период» не от чего.
  final VoidCallback? onSetFullPeriod;
  final VoidCallback onRefresh;

  const AnalyticsToolbar({
    super.key,
    required this.state,
    required this.onSetLast24Hours,
    required this.onSetLast7Days,
    required this.onRefresh,
    this.onSetFullPeriod,
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
              if (onSetFullPeriod != null) ...[
                const SizedBox(width: 8),
                _RangeChip(label: 'Весь период', onTap: onSetFullPeriod!),
              ],
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

// Единый дашборд кампании: блоки карточки кампании и блоки аукционной
// аналитики лежат в одной сетке, поэтому и порядок с ширинами у них общие.
const _kDashboardOrderKey = 'omni360-dashboard-order';
const _kDashboardWidthsKey = 'omni360-dashboard-widths';
const kAnalyticsBlockIds = [
  'summary',
  'states',
  'failures',
  'requests',
  'daily',
  'bidReport',
  'operatorReport',
];

typedef DashboardBlock = ({String id, bool isWide, Widget child});

/// Блок, который зависит от полной выгрузки показов: пока она грузится или
/// если она отвалилась, показываем состояние вместо пустой таблицы.
Widget _fromAllRecords(
  AsyncValue<List<CampaignImpressionRecord>> records,
  String title,
  Widget Function() build,
) {
  return records.when(
    data: (_) => build(),
    loading: () => CardSection(
      title: title,
      subtitle: 'Считаем по всем показам за период',
      child: const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(color: kAccent, strokeWidth: 2.5),
          ),
        ),
      ),
    ),
    error: (e, _) => CardSection(
      title: title,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          'Не удалось загрузить полную выгрузку показов за период.\n'
          'Попробуйте сузить период — обычно помогает.',
          style: const TextStyle(color: kTextSecondary, fontSize: 12),
        ),
      ),
    ),
  );
}

/// Сетка единого дашборда кампании.
///
/// Блоки аукционной аналитики строит сама, а блоки карточки кампании получает
/// готовыми через [extraBlocks] — так обе группы попадают в одну сетку с общим
/// перетаскиванием, ресайзом и сохранённым порядком.
class CampaignDashboardBody extends StatefulWidget {
  final CampaignAnalyticsState state;

  /// null — аналитика ещё грузится или не загрузилась. Блоки кампании при
  /// этом всё равно показываем: падение аналитики не должно уносить с собой
  /// всю карточку.
  final CampaignImpressionsPage? page;
  final CampaignAnalyticsAggregate aggregate;
  final LossReport lossReport;
  final ValueChanged<int> onPageChange;
  final Map<String, DashboardBlock> extraBlocks;
  final List<String> extraBlockIds;

  const CampaignDashboardBody({
    super.key,
    required this.state,
    required this.page,
    required this.aggregate,
    required this.lossReport,
    required this.onPageChange,
    this.extraBlocks = const {},
    this.extraBlockIds = const [],
  });

  @override
  State<CampaignDashboardBody> createState() => _CampaignDashboardBodyState();
}

class _CampaignDashboardBodyState extends State<CampaignDashboardBody> {
  late List<String> _order = _defaultOrder;
  Map<String, double> _widths = {};

  List<String> get _defaultOrder => [
    ...widget.extraBlockIds,
    ...kAnalyticsBlockIds,
  ];

  @override
  void initState() {
    super.initState();
    _loadOrder();
    _loadWidths();
  }

  Future<void> _loadOrder() async {
    final saved = await LocalOrderStore.instance.loadOrder(_kDashboardOrderKey);
    if (saved != null && mounted) {
      setState(
        () => _order = LocalOrderStore.instance.mergeOrder(
          _defaultOrder,
          saved,
        ),
      );
    }
  }

  Future<void> _loadWidths() async {
    final saved = await LocalOrderStore.instance.loadWidths(
      _kDashboardWidthsKey,
    );
    if (saved != null && mounted) {
      setState(() => _widths = saved);
    }
  }

  void _onReorder(List<DashboardBlock> newOrder) {
    final ids = newOrder.map((b) => b.id).toList();
    setState(() => _order = ids);
    LocalOrderStore.instance.saveOrder(_kDashboardOrderKey, ids);
  }

  void _onResize(String id, double fraction) {
    setState(() => _widths = {..._widths, id: fraction});
    LocalOrderStore.instance.saveWidths(_kDashboardWidthsKey, _widths);
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final page = widget.page;
    final aggregate = widget.aggregate;
    final lossReport = widget.lossReport;
    final onPageChange = widget.onPageChange;

    final records = page?.content ?? const <CampaignImpressionRecord>[];
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

    // Блоки аналитики добавляем только когда данные пришли: без них сетка
    // всё равно покажет карточку кампании.
    final analyticsBlocks = page == null
        ? const <String, DashboardBlock>{}
        : <String, DashboardBlock>{
      if (state.prefs.showSummary)
        'summary': (
          id: 'summary',
          isWide: true,
          child: CardSection(
            title: 'Сводка',
            subtitle: hasScreenFilter ? selectedScreenLabel : null,
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _MetricCard(
                  label: 'Запросов',
                  value: '${aggregate.totalRequests}',
                ),
                _MetricCard(label: 'Победы', value: '$wins'),
                _MetricCard(label: 'Проигрыши', value: '$losses'),
                if (hasScreenFilter)
                  _MetricCard(
                    label: 'Процент проигрышей',
                    value: '${(lossRate * 100).toStringAsFixed(1)}%',
                  ),
                _MetricCard(label: 'Успешные показы', value: '$successes'),
                _MetricCard(
                  label: '% успешных показов',
                  value: aggregate.totalRequests == 0
                      ? '—'
                      : '${(successes / aggregate.totalRequests * 100).toStringAsFixed(1)}%',
                ),
              ],
            ),
          ),
        ),
      if (state.prefs.showStateBreakdown)
        'states': (
          id: 'states',
          isWide: false,
          child: CardSection(
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
        ),
      if (state.prefs.showFailureBreakdown && failureCounts.isNotEmpty)
        'failures': (
          id: 'failures',
          isWide: false,
          child: CardSection(
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
        ),
      if (state.prefs.showRequestTable)
        'requests': (
          id: 'requests',
          isWide: false,
          child: CardSection(
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
        ),
      // Три блока ниже строятся из полной выгрузки всех показов — она грузится
      // отдельно от первой страницы и заметно дольше. Пока её нет, показываем
      // это прямо в блоке: пустая таблица неотличима от «данных нет».
      if (state.prefs.showDailyBreakdown)
        'daily': (
          id: 'daily',
          isWide: true,
          child: _fromAllRecords(
            state.allRecords,
            'Сводная по дням',
            () => DailyBreakdownSection(rows: lossReport.dailyBreakdown),
          ),
        ),
      if (state.prefs.showBidReport)
        'bidReport': (
          id: 'bidReport',
          isWide: true,
          child: _fromAllRecords(
            state.allRecords,
            'Поднять ставки',
            () => BidRaiseReportSection(rows: lossReport.bidRaiseRows),
          ),
        ),
      if (state.prefs.showOperatorReport)
        'operatorReport': (
          id: 'operatorReport',
          isWide: true,
          child: _fromAllRecords(
            state.allRecords,
            'К оператору',
            () => OperatorIssueReportSection(
              groups: lossReport.operatorIssueGroups,
            ),
          ),
        ),
    };

    final blocksById = <String, DashboardBlock>{
      ...widget.extraBlocks,
      ...analyticsBlocks,
    };

    final blocks = [
      for (final id in _order)
        if (blocksById.containsKey(id)) blocksById[id]!,
      // Блоки, которых не было в сохранённом порядке (новые или добавленные
      // карточкой кампании), иначе бы они просто не отрисовались.
      for (final entry in blocksById.entries)
        if (!_order.contains(entry.key)) entry.value,
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: ReorderableFlexWrap<DashboardBlock>(
        items: blocks,
        idOf: (b) => b.id,
        onReorder: _onReorder,
        itemBuilder: (context, b) => b.child,
        widthFractionOf: (b) => _widths[b.id] ?? (b.isWide ? 1.0 : 0.48),
        onResize: _onResize,
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
                '$value (${(ratio * 100).toStringAsFixed(1)}%)',
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
