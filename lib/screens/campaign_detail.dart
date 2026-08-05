import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../main.dart';
import '../providers/campaigns_provider.dart';
import '../providers/campaign_analytics_provider.dart';
import '../providers/favorites_provider.dart';
import '../services/favorites_store.dart';
import '../models/campaign.dart';
import '../models/campaign_analytics.dart';
import '../models/loss_report.dart';
import '../models/pace_summary.dart';
import 'campaign_analytics_screen.dart';
import '../widgets/campaign_recommendations.dart';
import '../widgets/loading_games.dart';
import '../widgets/stats_chart.dart';
import '../utils/pace_alerts.dart';
import '../utils/pace_colors.dart';
import '../utils/broadcast_schedule.dart';
import '../widgets/loading_placeholders.dart';

/// Счётчик показов в шапке — с разделителями разрядов: «123 500» читается, а
/// «123500» на ходу нет.
final _fmtCount = NumberFormat.decimalPattern('ru_RU');

const _kDetailBlockIds = [
  'overview',
  'recommendations',
  'planFact',
  'limits',
  'chart',
];

class CampaignDetailScreen extends ConsumerStatefulWidget {
  final String campaignId;

  const CampaignDetailScreen({super.key, required this.campaignId});

  @override
  ConsumerState<CampaignDetailScreen> createState() =>
      _CampaignDetailScreenState();
}

class _CampaignDetailScreenState extends ConsumerState<CampaignDetailScreen> {
  /// Календарь: выбирать можно только даты, когда кампания крутится, — от её
  /// старта до сегодня. Дальше конца кампании и в будущее ходить незачем.
  Future<void> _pickRange(Campaign campaign) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final start = DateTime.tryParse((campaign.startDate ?? '').trim());
    final end = DateTime.tryParse((campaign.endDate ?? '').trim());
    if (start == null) return;

    final firstDate = DateTime(start.year, start.month, start.day);
    // Верхняя граница — раньше из «сегодня» и даты окончания, но не раньше
    // старта, иначе showDateRangePicker падает на lastDate < firstDate.
    var lastDate = today;
    if (end != null) {
      final endDay = DateTime(end.year, end.month, end.day);
      if (endDay.isBefore(lastDate)) lastDate = endDay;
    }
    if (lastDate.isBefore(firstDate)) lastDate = firstDate;

    final state = ref.read(campaignAnalyticsProvider(widget.campaignId));
    final currentFrom = state.query.start;
    final currentTo = state.query.end;

    final picked = await showDateRangePicker(
      context: context,
      firstDate: firstDate,
      lastDate: lastDate,
      currentDate: today,
      initialDateRange: _initialRange(currentFrom, currentTo, firstDate, lastDate),
      helpText: 'Период показов',
      saveText: 'Применить',
      // Без flutter_localizations русской локали в календаре нет — просить её
      // здесь значит уронить пикер, поэтому оставляем локаль приложения.
    );
    if (picked == null || !mounted) return;

    // Берём день целиком: аналитика оперирует моментами времени, а календарь
    // отдаёт полночь — иначе последний выбранный день выпал бы из выборки.
    final from = DateTime(
      picked.start.year,
      picked.start.month,
      picked.start.day,
    );
    final to = DateTime(
      picked.end.year,
      picked.end.month,
      picked.end.day,
      23,
      59,
      59,
    );
    ref
        .read(campaignAnalyticsProvider(widget.campaignId).notifier)
        .setRange(from, to);
  }

  /// Весь срок кампании: от старта до «сейчас», но не дальше даты окончания.
  /// null — дат нет, и брать период не от чего.
  (DateTime, DateTime)? _fullPeriodOf(Campaign campaign) {
    final start = DateTime.tryParse((campaign.startDate ?? '').trim());
    if (start == null) return null;

    final now = DateTime.now();
    final end = DateTime.tryParse((campaign.endDate ?? '').trim());
    var to = now;
    if (end != null) {
      final endOfDay = DateTime(end.year, end.month, end.day, 23, 59, 59);
      if (endOfDay.isBefore(to)) to = endOfDay;
    }

    final from = DateTime(start.year, start.month, start.day);
    if (!to.isAfter(from)) return null;
    return (from, to);
  }

  /// Предупреждение перед выгрузкой всего периода — с настоящим объёмом.
  ///
  /// Сначала спрашиваем у бэкенда, сколько в периоде показов (один лёгкий
  /// запрос), и только потом предлагаем решение. Абстрактное «может занять
  /// несколько минут» ничего не говорит: на 20 тысячах это полминуты, а на 300
  /// тысячах — часы, и узнавать это через час ожидания неправильно.
  Future<bool> _confirmFullPeriod(
    BuildContext context,
    CampaignAnalyticsController controller,
    (DateTime, DateTime) range,
  ) async {
    final count = await controller.countImpressions(range.$1, range.$2);
    if (!context.mounted) return false;

    // Оценка снизу: запросы идут пачками по 6, каждый в среднем 1,5–5 секунд.
    final pages = count == null ? 0 : (count / 500).ceil();
    final minMinutes = (pages / 6 * 1.5 / 60).ceil();
    final maxMinutes = (pages / 6 * 5 / 60).ceil();
    final heavy = count != null && count > 100000;

    final go = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text(
          heavy ? 'Период очень большой' : 'Загрузить весь период?',
          style: const TextStyle(
            color: kTextPrimary,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          count == null
              ? 'Отчёты считаются по всем показам за период. Объём заранее '
                    'узнать не удалось — на крупных кампаниях это минуты. Блоки '
                    'наполняются по ходу загрузки.'
              : 'За период ${_fmtCount.format(count)} показов — это около '
                    '${_fmtCount.format(pages)} запросов к бэкенду и примерно '
                    '$minMinutes–$maxMinutes мин.\n\n'
                    '${heavy ? 'На таком объёме бэкенд начинает отдавать ошибки, и часть страниц может не дойти. Надёжнее выбрать период календарём — например, по неделям.\n\n' : ''}'
                    'Блоки наполняются по ходу, загрузку можно остановить в '
                    'любой момент — посчитается по тому, что успело прийти.',
          style: const TextStyle(color: kTextSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(
              backgroundColor: heavy ? const Color(0xFFE65100) : kAccent,
            ),
            child: Text(heavy ? 'Всё равно грузить' : 'Загрузить'),
          ),
        ],
      ),
    );
    return go ?? false;
  }

  DateTimeRange? _initialRange(
    DateTime from,
    DateTime to,
    DateTime firstDate,
    DateTime lastDate,
  ) {
    // Сохранённый период может выходить за границы кампании — тогда календарь
    // бросается на некорректном initialDateRange, лучше не подставлять его.
    if (from.isBefore(firstDate) || to.isAfter(lastDate)) return null;
    if (to.isBefore(from)) return null;
    return DateTimeRange(start: from, end: to);
  }

  @override
  Widget build(BuildContext context) {
    final campaignId = widget.campaignId;
    final detail = ref.watch(campaignDetailProvider(campaignId));
    final stats = ref.watch(campaignStatsProvider(campaignId));
    final photoCoverage = ref.watch(campaignPhotoCoverageProvider(campaignId));
    final inventory = ref.watch(campaignInventoryProvider(campaignId));
    final analytics = ref.watch(campaignAnalyticsProvider(campaignId));
    final analyticsController = ref.read(
      campaignAnalyticsProvider(campaignId).notifier,
    );
    final campaignName = detail.asData?.value.name ?? 'Кампания';

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
        actions: [
          // Звёздочка и здесь: чаще всего решение «за этой кампанией слежу»
          // принимается уже внутри карточки, а не в списке.
          Consumer(
            builder: (context, favRef, unusedChild) {
              final isFavorite = favRef.watch(
                favoritesProvider.select(
                  (f) => f.campaignIds.contains(campaignId),
                ),
              );
              return IconButton(
                tooltip: isFavorite ? 'Убрать из избранного' : 'В избранное',
                onPressed: () => favRef
                    .read(favoritesProvider.notifier)
                    .toggle(FavoriteKind.campaign, campaignId),
                icon: Icon(
                  isFavorite
                      ? Icons.star_rounded
                      : Icons.star_outline_rounded,
                  color: isFavorite ? const Color(0xFFF9A825) : null,
                ),
              );
            },
          ),
          IconButton(
            tooltip: 'Период показов',
            onPressed: detail.asData == null
                ? null
                : () => _pickRange(detail.asData!.value),
            icon: const Icon(Icons.date_range_rounded),
          ),
          IconButton(
            tooltip: 'Экспорт в Excel',
            onPressed: () =>
                exportAnalyticsToExcel(context, analytics, campaignName),
            icon: const Icon(Icons.ios_share_rounded),
          ),
          IconButton(
            tooltip: 'Настроить дашборд',
            onPressed: () =>
                openDashboardSettings(context, analytics, analyticsController),
            icon: const Icon(Icons.dashboard_customize_outlined),
          ),
          IconButton(
            tooltip: 'Фильтры',
            onPressed: () =>
                openAnalyticsFilters(context, analytics, analyticsController),
            icon: const Icon(Icons.tune_rounded),
          ),
        ],
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
        data: (campaign) {
          // Отчёт по отклонениям считается по всей выгрузке — на десятках тысяч
          // записей это ощутимая работа, поэтому один раз на отрисовку, а не по
          // разу на каждый блок, который его просит.
          final records = analytics.allRecords.asData?.value ?? const [];
          final lossReport = LossReportBuilder.build(records);

          final blocksById = <String, DashboardBlock>{
            // Пока считается выгрузка показов (на «всём периоде» это минуты),
            // верхнюю плитку занимает мини-игра. Блок существует только во
            // время загрузки и в сохранённый порядок не попадает.
            if (analytics.dumpInProgress)
              kLoadingGameBlockId: (
                id: kLoadingGameBlockId,
                isWide: false,
                child: const LoadingGameCard(key: ValueKey('loading-game')),
              ),
            // Статус, даты, фотоотчёты и сводка по запросам — один обзорный
            // блок: по отдельности это четыре почти пустые карточки.
            'overview': (
              id: 'overview',
              isWide: false,
              child: _OverviewCard(
                campaign: campaign,
                coverage: photoCoverage,
                // GID и оператор для списка экранов без ФО — из состава
                // кампании: в ответе про фотоотчёты их нет. Выгрузка показов
                // только дополняет подписи, если уже загружена.
                inventory: inventory.asData?.value ?? const {},
                records: records,
              ),
            ),
            // Текстовая справка для клиента — по умолчанию выключена в
            // настройках дашборда: нужна не каждый раз.
            if (analytics.prefs.showRecommendations)
              'recommendations': (
                id: 'recommendations',
                isWide: true,
                child: CampaignRecommendationsCard(
                  campaign: campaign,
                  stats: stats.asData?.value,
                  coverage: photoCoverage.asData?.value,
                  surfaceLabels: surfaceLabels(
                    inventory.asData?.value ?? const {},
                    records,
                  ),
                  lossReport: lossReport,
                  // Ошибки операторов попадают в письмо только если их доля от
                  // всех попыток выхода выше порога.
                  totalRequests:
                      analytics.aggregate.asData?.value.totalRequests ??
                      records.length,
                  periodStart: analytics.query.start,
                  periodEnd: analytics.query.end,
                  recordsLoading: analytics.dumpInProgress,
                ),
              ),
            'planFact': (
              id: 'planFact',
              isWide: true,
              child: stats.maybeWhen(
                data: (s) => _PlanFactCard(campaign: campaign, stats: s),
                orElse: () => _PlanFactCard(campaign: campaign, stats: null),
              ),
            ),
            'limits': (
              id: 'limits',
              isWide: false,
              child: _LimitsCard(
                campaign: campaign,
                stats: stats.asData?.value,
              ),
            ),
            // Блок «Подробная статистика» схлопнут в «План / Факт»: они
            // показывали одни и те же метрики, но только там есть шкалы.
            if (stats.maybeWhen(
              data: (s) => s.daily.isNotEmpty,
              orElse: () => false,
            ))
              'chart': (
                id: 'chart',
                isWide: true,
                child: stats.maybeWhen(
                  data: (s) => _ChartCard(stats: s),
                  orElse: () => const SizedBox.shrink(),
                ),
              ),
          };

          return Column(
            children: [
              AnalyticsToolbar(
                state: analytics,
                onSetLast24Hours: () {
                  final now = DateTime.now();
                  analyticsController.setRange(
                    now.subtract(const Duration(hours: 24)),
                    now,
                  );
                },
                onSetLast7Days: () {
                  final now = DateTime.now();
                  analyticsController.setRange(
                    now.subtract(const Duration(days: 7)),
                    now,
                  );
                },
                onSetFullPeriod: _fullPeriodOf(campaign) == null
                    ? null
                    : () async {
                        final range = _fullPeriodOf(campaign)!;
                        // Весь период выгружается целиком, без предела по
                        // страницам. Спрашиваем заранее и с реальным объёмом,
                        // чтобы это не было сюрпризом на час.
                        final go = await _confirmFullPeriod(
                          context,
                          analyticsController,
                          range,
                        );
                        if (!go) return;
                        analyticsController.setRange(range.$1, range.$2);
                      },
                onRefresh: analyticsController.fetchImpressions,
              ),
              // Предупреждения о темпе — здесь, рядом с выбором периода:
              // в карточке «План / Факт» их замечали только после прокрутки.
              _PaceAlertsBar(
                campaign: campaign,
                stats: stats.valueOrNull,
              ),
              // Тонкая полоска в 2 пикселя терялась, и смена периода выглядела
              // так, будто ничего не происходит. Теперь это заметная плашка
              // с крутилкой сразу под выбором периода.
              if (analytics.impressions.isLoading || analytics.dumpInProgress)
                Container(
                  width: double.infinity,
                  color: Colors.white,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: kAccentLight,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: kAccent.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: kAccent,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            // Счётчик вместо «идёт загрузка»: на большом
                            // периоде без него непонятно, движется ли дело.
                            analytics.impressions.isLoading
                                ? 'Загружаем данные за выбранный период…'
                                : analytics.dumpTotal > 0
                                ? 'Догружаем показы для отчётов: '
                                      '${_fmtCount.format(analytics.dumpLoaded)}'
                                      ' из '
                                      '${_fmtCount.format(analytics.dumpTotal)}'
                                      ' — отчёты пополняются по ходу'
                                : 'Дашборд готов, догружаем полную выгрузку '
                                      'показов для отчётов…',
                            style: const TextStyle(
                              color: kAccent,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        // Остановить можно в любой момент: отчёты посчитаются
                        // по тому, что успело прийти. Раньше выгрузку нечем
                        // было прервать — только перезагрузкой страницы.
                        if (analytics.dumpInProgress)
                          TextButton(
                            onPressed: analyticsController.cancelDump,
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              minimumSize: const Size(0, 28),
                              foregroundColor: kAccent,
                            ),
                            child: const Text(
                              'Остановить',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              if (analytics.impressions.hasError)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Text(
                    analyticsErrorMessage(analytics.impressions.error!),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: kTextSecondary, fontSize: 12),
                  ),
                ),
              Expanded(
                // Блоки кампании и блоки аналитики — одна сетка с общим
                // порядком и ширинами. Аналитика может ещё грузиться или
                // отвалиться по таймауту: карточка кампании от этого не
                // должна пропадать, поэтому page передаём как есть.
                child: CampaignDashboardBody(
                  state: analytics,
                  page: analytics.impressions.asData?.value,
                  aggregate:
                      analytics.aggregate.asData?.value ??
                      CampaignAnalyticsAggregate.empty(),
                  lossReport: lossReport,
                  onPageChange: analyticsController.setPage,
                  onLoadAllRecords: analyticsController.loadAllRecords,
                  extraBlocks: blocksById,
                  extraBlockIds: _kDetailBlockIds,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ── Status card ───────────────────────────────────────────────────────────────

class _StatusCard extends StatelessWidget {
  final Campaign campaign;
  final bool bare;
  const _StatusCard({required this.campaign, this.bare = false});

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = campaignStatusPalette(campaign.statusKind);
    final label = campaign.displayStatus;
    return _Card(
      bare: bare,
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: fg,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
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

}

// ── Dates card ────────────────────────────────────────────────────────────────

class _DatesCard extends StatelessWidget {
  final Campaign campaign;
  final bool bare;
  const _DatesCard({required this.campaign, this.bare = false});

  @override
  Widget build(BuildContext context) {
    if (campaign.startDate == null && campaign.endDate == null) {
      return const SizedBox.shrink();
    }
    return _Card(
      bare: bare,
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

class _PhotoCoverageCard extends StatelessWidget {
  final AsyncValue<CampaignPhotoCoverage> coverage;

  /// Состав кампании — источник GID и оператора для списка экранов без
  /// фотоотчётов: в ответе про фотоотчёты их нет.
  final Map<int, CampaignInventoryRef> inventory;

  /// Выгрузка показов, если она уже загружена, — только дополняет подписи
  /// стороной и адресом конкретного показа. Пустой список ничего не ломает.
  final List<CampaignImpressionRecord> records;

  final bool bare;
  const _PhotoCoverageCard({
    required this.coverage,
    this.inventory = const {},
    this.records = const [],
    this.bare = false,
  });

  @override
  Widget build(BuildContext context) {
    return _Card(
      bare: bare,
      child: coverage.when(
        loading: () => const Row(
          children: [
            Icon(Icons.photo_camera_outlined, size: 18, color: kTextSecondary),
            SizedBox(width: 8),
            Text(
              'Фотоотчёты по сторонам: загрузка...',
              style: TextStyle(color: kTextSecondary, fontSize: 13),
            ),
          ],
        ),
        error: (_, __) => const Row(
          children: [
            Icon(Icons.photo_camera_outlined, size: 18, color: kTextSecondary),
            SizedBox(width: 8),
            Text(
              'Фотоотчёты по сторонам: нет данных',
              style: TextStyle(color: kTextSecondary, fontSize: 13),
            ),
          ],
        ),
        data: (value) {
          final percent = value.percent.clamp(0, 100).toDouble();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(
                    Icons.photo_camera_outlined,
                    size: 18,
                    color: kTextSecondary,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Фотоотчёты по сторонам',
                    style: TextStyle(
                      color: kTextPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '${percent.toStringAsFixed(1)}% (${value.sidesWithPhoto}/${value.totalSides})',
                style: const TextStyle(
                  color: kTextPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: percent / 100,
                  backgroundColor: const Color(0xFFE8EAF6),
                  valueColor: const AlwaysStoppedAnimation(kAccent),
                  minHeight: 6,
                ),
              ),
              // Разбор недостающих ФО — в диалоге, а не раскрытием внутри
              // блока: список бывает в сотни строк и ломал бы заданную
              // пользователем высоту блока.
              if (value.missing.isNotEmpty) ...[
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    // Карту подписей строим по клику, а не на каждой отрисовке:
                    // в выгрузке показов бывают десятки тысяч записей.
                    onPressed: () => _showMissingPhotoSides(
                      context,
                      value,
                      surfaceLabels(inventory, records),
                    ),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      minimumSize: const Size(0, 32),
                      foregroundColor: kAccent,
                    ),
                    icon: const Icon(Icons.list_alt_rounded, size: 16),
                    label: Text(
                      'Показать GID экранов без фотоотчётов '
                      '(${value.missing.length})',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// Подписи поверхностей для списка экранов без фотоотчётов.
///
/// Основной источник — состав кампании из детального ответа: он уже загружен и
/// закеширован, так что GID и оператор достаются без единого запроса и не
/// зависят от выбранного периода. Выгрузка показов, если она уже есть на руках,
/// только дополняет: там ещё указаны сторона и адрес конкретного показа.
Map<int, SurfaceLabel> surfaceLabels(
  Map<int, CampaignInventoryRef> inventory,
  List<CampaignImpressionRecord> records,
) {
  final labels = <int, SurfaceLabel>{
    for (final ref in inventory.values)
      ref.id: (
        gid: ref.gid,
        side: '',
        address: ref.address,
        operatorName: ref.operatorName,
        city: ref.city,
      ),
  };

  // Дополняем пустые поля тем, что есть в показах; уже известное не
  // перезаписываем — состав кампании точнее.
  for (final entry in surfaceLabelsFromRecords(records).entries) {
    final known = labels[entry.key];
    if (known == null) {
      labels[entry.key] = entry.value;
      continue;
    }
    labels[entry.key] = (
      gid: known.gid.isNotEmpty ? known.gid : entry.value.gid,
      side: known.side.isNotEmpty ? known.side : entry.value.side,
      address: known.address.isNotEmpty ? known.address : entry.value.address,
      operatorName: known.operatorName.isNotEmpty
          ? known.operatorName
          : entry.value.operatorName,
      city: known.city.isNotEmpty ? known.city : entry.value.city,
    );
  }

  return labels;
}

/// Список сторон без фотоотчёта: GID, адрес, оператор и число показов.
void _showMissingPhotoSides(
  BuildContext context,
  CampaignPhotoCoverage coverage,
  Map<int, SurfaceLabel> labels,
) {
  final fmtNum = NumberFormat.decimalPattern('ru_RU');
  final missing = coverage.missing;

  SurfaceLabel? labelOf(PhotoMissingSide side) =>
      side.inventoryId == null ? null : labels[side.inventoryId];

  // Заголовок строки: GID, если он известен, иначе внутреннее имя — оно хотя
  // бы называет улицу и оператора в своём префиксе.
  String titleOf(PhotoMissingSide side) {
    final label = labelOf(side);
    final gid = label?.gid ?? '';
    if (gid.isEmpty) return side.name.isEmpty ? 'Без названия' : side.name;
    final sideCode = label?.side ?? '';
    // GID уже обычно содержит сторону («645B»), дублировать её не нужно.
    return gid.endsWith(sideCode) || sideCode.isEmpty ? gid : '$gid $sideCode';
  }

  String subtitleOf(PhotoMissingSide side) {
    final label = labelOf(side);
    if (label == null) return side.name;
    final parts = [
      if (label.address.isNotEmpty) label.address,
      if (label.operatorName.isNotEmpty) label.operatorName,
      if (label.city.isNotEmpty && !label.address.contains(label.city))
        label.city,
    ];
    return parts.isEmpty ? side.name : parts.join(' · ');
  }

  final withoutLabels = missing.where((side) {
    final label = labelOf(side);
    return label == null || label.gid.isEmpty;
  }).length;

  showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: Colors.white,
      title: const Text(
        'Экраны без фотоотчётов',
        style: TextStyle(
          color: kTextPrimary,
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      ),
      content: SizedBox(
        width: 620,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${missing.length} сторон, '
              '${fmtNum.format(coverage.missingShows)} показов без '
              'подтверждения фотоотчётом',
              style: const TextStyle(color: kTextSecondary, fontSize: 12),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final side in missing)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    titleOf(side),
                                    style: const TextStyle(
                                      color: kTextPrimary,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    subtitleOf(side),
                                    style: const TextStyle(
                                      color: kTextSecondary,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              '${fmtNum.format(side.shows)} показов',
                              style: const TextStyle(
                                color: kTextSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            // Обычно не срабатывает: состав кампании приходит вместе с самой
            // кампанией. Но если поверхности в нём не окажется — лучше сказать
            // об этом, чем молча показать внутреннее имя как GID.
            if (withoutLabels > 0) ...[
              const SizedBox(height: 12),
              Text(
                'Для $withoutLabels из ${missing.length} экранов GID не нашёлся '
                'в составе кампании — показано внутреннее имя поверхности.',
                style: const TextStyle(color: Color(0xFFE65100), fontSize: 11),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          // Список нужен, чтобы отправить его оператору, — копируем целиком,
          // вместе с адресом: по одному GID оператор экран не найдёт.
          onPressed: () async {
            await Clipboard.setData(
              ClipboardData(
                text: missing
                    .map(
                      (side) =>
                          '${titleOf(side)} — ${subtitleOf(side)} — '
                          '${side.shows} показов',
                    )
                    .join('\n'),
              ),
            );
            if (!dialogContext.mounted) return;
            ScaffoldMessenger.of(dialogContext).showSnackBar(
              const SnackBar(content: Text('Список скопирован')),
            );
          },
          child: const Text('Скопировать список'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext),
          style: FilledButton.styleFrom(backgroundColor: kAccent),
          child: const Text('Закрыть'),
        ),
      ],
    ),
  );
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

    // ПЛАН приоритетно берём из /impression-stats (planBudget/planDailyBudget/
    // planOts) — там он есть даже для кампаний, у которых budget/dailyBudget/
    // ots не заполнены на уровне самой кампании (detail endpoint). Данные
    // кампании — запасной вариант, если в статистике плана нет.
    final planBudget = (s != null && s.planBudget > 0)
        ? s.planBudget
        : campaign.budget;
    final planDaily = (s != null && s.planDailyBudget > 0)
        ? s.planDailyBudget
        : campaign.dailyBudget;
    // По OTS план берём только из самой кампании: otsCount и reservedBudgetStat
    // в статистике заполнены и тогда, когда лимит по OTS не выставлен, — это
    // расчётные величины, а не план. Нет лимита в кампании — значит прочерк.
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

    // В час — сразу за суточным, чтобы бюджетные метрики шли подряд.
    if (s != null && (s.hourlyBudgetPlan > 0 || s.hourlyBudgetFact > 0)) {
      rows.add(
        _PlanFactRow(
          label: 'В час',
          plan: s.hourlyBudgetPlan > 0
              ? fmtRub.format(s.hourlyBudgetPlan)
              : '—',
          fact: s.hourlyBudgetFact > 0
              ? fmtRub.format(s.hourlyBudgetFact)
              : null,
          ratio: (s.hourlyBudgetPlan > 0 && s.hourlyBudgetFact > 0)
              ? s.hourlyBudgetFact / s.hourlyBudgetPlan
              : null,
        ),
      );
    }

    // OTS — показываем если есть план ИЛИ факт
    final factOts = (s != null && s.factOts > 0) ? s.factOts : null;
    // Измеренного OTS у части кампаний нет, и факт подставляется из
    // смоделированного/оценочного значения — подписываем честно.
    final otsEstimated = s?.factOtsIsEstimated ?? false;
    if ((planOts != null && planOts > 0) || factOts != null) {
      rows.add(
        _PlanFactRow(
          label: otsEstimated ? 'OTS (оценка)' : 'OTS',
          plan: (planOts != null && planOts > 0) ? fmtNum.format(planOts) : '—',
          fact: factOts != null
              ? '${otsEstimated ? '≈' : ''}${fmtNum.format(factOts)}'
              : null,
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

    // У CPM нет плана — показываем как факт без шкалы.
    if (s != null && s.cpm > 0) {
      rows.add(
        _PlanFactRow(
          label: 'CPM',
          plan: '—',
          fact: fmtRub.format(s.cpm),
          ratio: null,
        ),
      );
    }

    if (rows.isEmpty) return const SizedBox.shrink();

    // Плашки-предупреждения переехали в шапку страницы, рядом с выбором
    // периода: там они видны сразу, а не только когда доскроллишь до карточки.
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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

  /// Цвет шкалы по близости факта к плану.
  ///
  /// Раньше логика была обратной: чем меньше освоено, тем «зеленее». Из-за
  /// этого кампания, освоившая 35% бюджета к концу срока, выглядела здоровой,
  /// а почти выполнившая план — красной. Зелёный теперь означает «идём по
  /// плану», а не «мало потратили».
  Color get _barColor => paceColor(ratio);

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

/// Обзор кампании: статус, даты и фотоотчёты в одном блоке. По отдельности
/// это были три карточки в одну-две строки каждая.
class _OverviewCard extends StatelessWidget {
  final Campaign campaign;
  final AsyncValue<CampaignPhotoCoverage> coverage;

  /// Состав кампании и выгрузка показов — для подписей в списке экранов без
  /// фотоотчётов.
  final Map<int, CampaignInventoryRef> inventory;
  final List<CampaignImpressionRecord> records;

  const _OverviewCard({
    required this.campaign,
    required this.coverage,
    this.inventory = const {},
    this.records = const [],
  });

  @override
  Widget build(BuildContext context) {
    // Сводка по запросам живёт в блоке с диаграммой — там она о том же, о чём
    // диаграмма, и не отрывает цифры от разбивки.
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StatusCard(campaign: campaign, bare: true),
          const SizedBox(height: 10),
          _DatesCard(campaign: campaign, bare: true),
          const SizedBox(height: 10),
          _PhotoCoverageCard(
            coverage: coverage,
            inventory: inventory,
            records: records,
            bare: true,
          ),
        ],
      ),
    );
  }
}

/// Полоса предупреждений о темпе в шапке дашборда.
///
/// Расписание берётся из самой кампании — детальный ответ его содержит, так
/// что лишнего запроса здесь нет.
class _PaceAlertsBar extends StatelessWidget {
  final Campaign campaign;
  final CampaignStats? stats;

  const _PaceAlertsBar({required this.campaign, required this.stats});

  @override
  Widget build(BuildContext context) {
    final s = stats;
    if (s == null) return const SizedBox.shrink();

    // Внутридневные алерты живут только внутри окна вещания: их темп считается
    // от доли прошедшего эфира. Вне окна они молчат — и раньше это выглядело
    // так, будто у кампании всё в порядке. Поэтому рядом идёт проверка по
    // всему периоду, которая от времени суток не зависит.
    final alerts = buildAlerts(campaign, s);
    final periodChip = _periodChip(s);

    if (alerts.isEmpty && periodChip == null) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          if (periodChip != null) periodChip,
          ...alerts.map((a) => _AlertBanner(alert: a)),
        ],
      ),
    );
  }

  /// Отставание по бюджету за весь период кампании.
  Widget? _periodChip(CampaignStats s) {
    final spent = (campaign.spent != null && campaign.spent! > 0)
        ? campaign.spent!
        : s.factBudget;
    final pace = CampaignPaceSummary.fromCampaign(
      campaign,
      DateTime.now(),
      spentOverride: spent,
      budgetOverride: s.planBudget,
    );
    if (pace.planToNow <= 0) return null;

    final ratio = pace.pacePctNow;
    // Отклонение меньше 10% — шум, о нём сообщать незачем.
    if (ratio >= 0.9 && ratio <= 1.1) return null;

    final behind = ratio < 1;
    final color = behind ? const Color(0xFF1565C0) : const Color(0xFFC62828);
    final bg = behind ? const Color(0xFFE3F2FD) : const Color(0xFFFFEBEE);
    final fmtRub = NumberFormat.currency(
      locale: 'ru_RU',
      symbol: '₽',
      decimalDigits: 0,
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(behind ? '📉' : '⚡', style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              behind
                  ? 'За период отстаём от плана на '
                        '${fmtRub.format(pace.shortfallNow)} '
                        '(${(ratio * 100).toStringAsFixed(0)}% плана)'
                  : 'За период идём выше плана: '
                        '${(ratio * 100).toStringAsFixed(0)}% плана',
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

/// Насколько выбран суточный и часовой лимит прямо сейчас.
///
/// Рекомендуемый лимит — остаток бюджета, разложенный по оставшимся дням и
/// часам вещания (та же арифметика, что в таблице темпов). Факт — сколько
/// реально ушло за сегодня и за последний час.
class _LimitsCard extends StatelessWidget {
  final Campaign campaign;
  final CampaignStats? stats;

  const _LimitsCard({required this.campaign, required this.stats});

  @override
  Widget build(BuildContext context) {
    final fmtRub = NumberFormat.currency(
      locale: 'ru_RU',
      symbol: '₽',
      decimalDigits: 0,
    );

    final spent = (campaign.spent != null && campaign.spent! > 0)
        ? campaign.spent!
        : (stats?.factBudget ?? 0);
    // Расписание берём из самой кампании: детальный ответ его уже содержит,
    // так что лишнего запроса здесь не нужно. Бюджет — с запасным вариантом
    // из статистики: в детальном ответе он не всегда заполнен, и без него
    // рекомендуемый лимит молча получался нулевым.
    final pace = CampaignPaceSummary.fromCampaign(
      campaign,
      DateTime.now(),
      spentOverride: spent,
      budgetOverride: stats?.planBudget,
      currentDailyLimit: stats?.planDailyBudget,
      currentHourlyLimit: stats?.hourlyBudgetPlan,
    );

    // Раньше при нерассчитанном лимите блок писал «нет бюджета или дат» —
    // причина могла быть совсем другой (кампания закончилась, бюджет уже
    // израсходован), и сообщение просто вводило в заблуждение. Называем
    // настоящую причину, а факт показываем всегда: он от лимита не зависит.
    final reason = _whyNoLimit(pace);

    // Раньше эти строки рисовались через «План / Факт», и рекомендуемый лимит
    // читался как установленный. Подписываем все три величины явно.
    Widget row(
      String label,
      double recommended,
      double? current,
      double? fact,
      String hint,
    ) {
      final hasFact = fact != null && fact > 0;
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: kTextPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 16,
              runSpacing: 4,
              children: [
                _value(
                  'Рекомендуем',
                  recommended > 0 ? fmtRub.format(recommended) : '—',
                  kAccent,
                ),
                _value(
                  'Установлен',
                  (current != null && current > 0)
                      ? fmtRub.format(current)
                      : '—',
                  kTextSecondary,
                ),
                _value(
                  'Ушло',
                  hasFact ? fmtRub.format(fact) : '—',
                  kTextPrimary,
                ),
                if (hasFact && recommended > 0)
                  _value(
                    'Выполнение',
                    '${(fact / recommended * 100).toStringAsFixed(0)}% '
                        'от рекомендуемого',
                    // Та же шкала, что у остальных блоков: любое превышение
                    // здесь красилось красным, а отставание до 70% — зелёным.
                    paceColor(fact / recommended),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              hint,
              style: const TextStyle(color: kTextSecondary, fontSize: 11),
            ),
          ],
        ),
      );
    }

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Выполнение лимита',
            style: TextStyle(
              color: kTextPrimary,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            reason ??
                (pace.scheduleResolved && !pace.hasTimeRestrictions
                    ? 'Кампания идёт круглосуточно'
                    : 'Рекомендуемый лимит — по расписанию вещания'),
            style: const TextStyle(color: kTextSecondary, fontSize: 11),
          ),
          const SizedBox(height: 8),
          row(
            'В сутки',
            pace.dailyLimit,
            pace.currentDailyLimit,
            stats?.factDailyBudget,
            pace.broadcastDaysLeft > 0
                ? 'Рекомендуем остаток ÷ ${pace.broadcastDaysLeft} дн. вещания'
                : 'Рекомендуемый лимит не рассчитан',
          ),
          row(
            'В час',
            pace.hourlyLimit,
            pace.currentHourlyLimit,
            stats?.hourlyBudgetFact,
            pace.broadcastHoursLeft > 0
                ? 'Рекомендуем остаток ÷ '
                      '${pace.broadcastHoursLeft.toStringAsFixed(0)} ч вещания'
                : 'Рекомендуемый лимит не рассчитан',
          ),
        ],
      ),
    );
  }

  Widget _value(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: kTextSecondary, fontSize: 10),
        ),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  /// Почему рекомендуемый лимит равен нулю. null — он рассчитан нормально.
  String? _whyNoLimit(CampaignPaceSummary pace) {
    if (pace.dailyLimit > 0 || pace.hourlyLimit > 0) return null;
    if (pace.budget <= 0) return 'Бюджет кампании не задан';
    if (pace.startDate == null || pace.endDate == null) {
      return 'Даты кампании не заданы';
    }
    if (pace.remainingBudget <= 0) return 'Бюджет кампании уже израсходован';
    if (pace.daysLeft <= 0) return 'Кампания уже закончилась';
    return 'Впереди нет часов вещания по расписанию';
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
    // pct — это отклонение, а не доля от темпа. Прежняя формулировка «100% от
    // ожидаемого темпа» читалась как «ровно по плану», хотя означала ровно
    // наоборот: не потрачено ничего.
    final text = isNoExits
        ? 'Нет выходов за последний час'
        : '${isOver ? 'Перерасход' : 'Недотрата'} ${alert.metric}: '
              'на ${alert.pct.toStringAsFixed(0)}% '
              '${isOver ? 'выше' : 'ниже'} ожидаемого темпа';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      // Плашка сама подбирает ширину по тексту: она живёт в Wrap в шапке, а
      // Expanded внутри Row там упал бы на неограниченной ширине.
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(icon, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 8),
          Flexible(
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

  /// true — отдать содержимое без рамки и отступов: карточку вкладывают в
  /// другую карточку, и вторая рамка вокруг неё выглядит мусором.
  final bool bare;

  const _Card({required this.child, this.bare = false});

  @override
  Widget build(BuildContext context) => bare
      ? child
      : Container(
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
          // При заданной вручную высоте прокручиваем содержимое внутри
          // карточки: прокрутка вокруг неё срезала углы и тень.
          child: LayoutBuilder(
            builder: (context, constraints) => constraints.hasBoundedHeight
                ? SingleChildScrollView(child: child)
                : child,
          ),
        );
}
