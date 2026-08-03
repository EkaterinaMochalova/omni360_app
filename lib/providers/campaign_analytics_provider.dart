import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../api/omni360_client.dart';
import '../models/campaign_analytics.dart';

class CampaignAnalyticsQuery {
  final DateTime start;
  final DateTime end;
  final Set<String> states;
  final Set<String> failureReasons;
  final String address;
  final String inventoryGid;
  final int page;
  final int size;

  const CampaignAnalyticsQuery({
    required this.start,
    required this.end,
    required this.states,
    required this.failureReasons,
    required this.address,
    required this.inventoryGid,
    required this.page,
    required this.size,
  });

  factory CampaignAnalyticsQuery.initial() {
    final now = DateTime.now();
    return CampaignAnalyticsQuery(
      start: now.subtract(const Duration(hours: 24)),
      end: now,
      states: const {},
      failureReasons: const {},
      address: '',
      inventoryGid: '',
      page: 0,
      size: 50,
    );
  }

  CampaignAnalyticsQuery copyWith({
    DateTime? start,
    DateTime? end,
    Set<String>? states,
    Set<String>? failureReasons,
    String? address,
    String? inventoryGid,
    int? page,
    int? size,
  }) {
    return CampaignAnalyticsQuery(
      start: start ?? this.start,
      end: end ?? this.end,
      states: states ?? this.states,
      failureReasons: failureReasons ?? this.failureReasons,
      address: address ?? this.address,
      inventoryGid: inventoryGid ?? this.inventoryGid,
      page: page ?? this.page,
      size: size ?? this.size,
    );
  }
}

class CampaignAnalyticsState {
  final AsyncValue<CampaignImpressionsPage> impressions;
  final AsyncValue<CampaignAnalyticsAggregate> aggregate;
  final AsyncValue<CampaignAnalyticsFiltersData> filters;
  final CampaignAnalyticsDashboardPrefs prefs;
  final CampaignAnalyticsQuery query;

  /// Все показы за выбранный период (все страницы), собранные попутно с
  /// расчётом [aggregate] — используются отчётами по ставкам/оператору и
  /// экспортом в Excel, чтобы не тянуть данные с бэкенда повторно.
  final AsyncValue<List<CampaignImpressionRecord>> allRecords;

  /// Вся ли выгрузка догрузилась. false — часть страниц не пришла или период
  /// оказался шире предела; отчёты по ним всё равно строятся, но об этом надо
  /// сказать, а не показывать неполные цифры как полные.
  final bool allRecordsComplete;

  /// Когда данные пришли с бэкенда. Нужна из-за кеша: вернувшись в карточку,
  /// пользователь видит цифры, посчитанные раньше, и должен понимать, на какой
  /// момент они посчитаны — иначе кеш выглядит как свежая загрузка.
  final DateTime? loadedAt;

  /// Выгрузка ещё идёт, но часть данных уже пришла: [allRecords] заполнен
  /// промежуточным срезом. Отдельный признак нужен потому, что `isLoading` у
  /// [allRecords] снимается с первым же срезом.
  final bool dumpInProgress;

  /// Сколько показов уже загружено и сколько всего ожидается.
  final int dumpLoaded;
  final int dumpTotal;

  const CampaignAnalyticsState({
    required this.impressions,
    required this.aggregate,
    required this.filters,
    required this.prefs,
    required this.query,
    required this.allRecords,
    this.allRecordsComplete = true,
    this.loadedAt,
    this.dumpInProgress = false,
    this.dumpLoaded = 0,
    this.dumpTotal = 0,
  });

  factory CampaignAnalyticsState.initial() => CampaignAnalyticsState(
    impressions: const AsyncValue.loading(),
    aggregate: const AsyncValue.loading(),
    filters: const AsyncValue.loading(),
    prefs: const CampaignAnalyticsDashboardPrefs.defaults(),
    query: CampaignAnalyticsQuery.initial(),
    allRecords: const AsyncValue.loading(),
  );

  CampaignAnalyticsState copyWith({
    AsyncValue<CampaignImpressionsPage>? impressions,
    AsyncValue<CampaignAnalyticsAggregate>? aggregate,
    AsyncValue<CampaignAnalyticsFiltersData>? filters,
    CampaignAnalyticsDashboardPrefs? prefs,
    CampaignAnalyticsQuery? query,
    AsyncValue<List<CampaignImpressionRecord>>? allRecords,
    bool? allRecordsComplete,
    DateTime? loadedAt,
    bool? dumpInProgress,
    int? dumpLoaded,
    int? dumpTotal,
  }) {
    return CampaignAnalyticsState(
      impressions: impressions ?? this.impressions,
      aggregate: aggregate ?? this.aggregate,
      filters: filters ?? this.filters,
      prefs: prefs ?? this.prefs,
      query: query ?? this.query,
      allRecords: allRecords ?? this.allRecords,
      allRecordsComplete: allRecordsComplete ?? this.allRecordsComplete,
      loadedAt: loadedAt ?? this.loadedAt,
      dumpInProgress: dumpInProgress ?? this.dumpInProgress,
      dumpLoaded: dumpLoaded ?? this.dumpLoaded,
      dumpTotal: dumpTotal ?? this.dumpTotal,
    );
  }
}

class CampaignAnalyticsController
    extends StateNotifier<CampaignAnalyticsState> {
  CampaignAnalyticsController(this.campaignId)
    : _client = Omni360Client(),
      super(CampaignAnalyticsState.initial()) {
    _loadPrefs();
    _loadFilters();
    fetchImpressions();
  }

  final String campaignId;
  final Omni360Client _client;

  /// Номер текущей выгрузки. Смена периода наращивает его, и промежуточные
  /// срезы прошлой выгрузки перестают попадать в состояние.
  int _dumpGeneration = 0;

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  String get _prefsKey => 'campaign_analytics_dashboard_prefs';

  Future<void> _loadPrefs() async {
    final raw = await _storage.read(key: _prefsKey);
    if (raw == null) return;

    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      state = state.copyWith(
        prefs: CampaignAnalyticsDashboardPrefs.fromJson(decoded),
      );
    } catch (_) {
      // Ignore corrupted preferences and keep defaults.
    }
  }

  Future<void> _savePrefs(CampaignAnalyticsDashboardPrefs prefs) async {
    await _storage.write(key: _prefsKey, value: jsonEncode(prefs.toJson()));
  }

  Future<void> _loadFilters() async {
    try {
      final response = await _client.dio.get(
        '/api/v1.0/clients/campaigns/$campaignId/filters-list',
      );
      state = state.copyWith(
        filters: AsyncValue.data(
          CampaignAnalyticsFiltersData.fromJson(
            response.data as Map<String, dynamic>,
          ),
        ),
      );
    } catch (e, st) {
      state = state.copyWith(filters: AsyncValue.error(e, st));
    }
  }

  Future<void> fetchImpressions() async {
    _dumpGeneration++;
    state = state.copyWith(
      impressions: const AsyncValue.loading(),
      aggregate: const AsyncValue.loading(),
      allRecords: const AsyncValue.loading(),
      allRecordsComplete: true,
      dumpInProgress: true,
      dumpLoaded: 0,
      dumpTotal: 0,
    );

    // Первая страница и полная выгрузка всех записей — независимые запросы, и
    // ждать их вместе было ошибкой: дашборд не показывался, пока не скачается
    // вся выгрузка, а её таймаут ронял заодно и лёгкую первую страницу.
    // Теперь каждая часть кладёт свой результат сама, как только готова.
    final query = state.query;
    await Future.wait([_loadFirstPage(query), _loadAggregateAndRecords(query)]);
  }

  Future<void> _loadFirstPage(CampaignAnalyticsQuery query) async {
    try {
      final response = await _fetchPage(query);
      state = state.copyWith(
        impressions: AsyncValue.data(
          CampaignImpressionsPage.fromJson(
            response.data as Map<String, dynamic>,
          ),
        ),
        loadedAt: DateTime.now(),
      );
    } on DioException catch (e, st) {
      final serverDetails = _extractServerDetails(e);
      state = state.copyWith(
        impressions: AsyncValue.error(
          serverDetails == null ? e : Exception(serverDetails),
          st,
        ),
      );
    } catch (e, st) {
      state = state.copyWith(impressions: AsyncValue.error(e, st));
    }
  }

  Future<void> _loadAggregateAndRecords(CampaignAnalyticsQuery query) async {
    final generation = _dumpGeneration;
    try {
      final result = await _fetchAllRecords(
        query,
        onProgress: (records, total) {
          // Смена периода отменяет старую выгрузку: её промежуточные срезы не
          // должны затирать данные нового запроса.
          if (generation != _dumpGeneration) return;
          state = state.copyWith(
            aggregate: AsyncValue.data(
              CampaignAnalyticsAggregate.fromRecords(records),
            ),
            allRecords: AsyncValue.data(records),
            allRecordsComplete: false,
            dumpInProgress: true,
            dumpLoaded: records.length,
            dumpTotal: total,
            loadedAt: DateTime.now(),
          );
        },
      );
      if (generation != _dumpGeneration) return;
      state = state.copyWith(
        aggregate: AsyncValue.data(
          CampaignAnalyticsAggregate.fromRecords(result.records),
        ),
        allRecords: AsyncValue.data(result.records),
        allRecordsComplete: result.complete,
        dumpInProgress: false,
        dumpLoaded: result.records.length,
        loadedAt: DateTime.now(),
      );
    } on DioException catch (e, st) {
      if (generation != _dumpGeneration) return;
      final serverDetails = _extractServerDetails(e);
      final error = serverDetails == null ? e : Exception(serverDetails);
      state = state.copyWith(
        aggregate: AsyncValue.error(error, st),
        allRecords: AsyncValue.error(error, st),
        dumpInProgress: false,
      );
    } catch (e, st) {
      if (generation != _dumpGeneration) return;
      state = state.copyWith(
        aggregate: AsyncValue.error(e, st),
        allRecords: AsyncValue.error(e, st),
        dumpInProgress: false,
      );
    }
  }

  Future<void> setRange(DateTime start, DateTime end) async {
    state = state.copyWith(
      query: state.query.copyWith(start: start, end: end, page: 0),
    );
    await fetchImpressions();
  }

  /// Повторить выгрузку показов — когда часть страниц не дошла.
  Future<void> loadAllRecords() async {
    _dumpGeneration++;
    state = state.copyWith(
      aggregate: const AsyncValue.loading(),
      allRecords: const AsyncValue.loading(),
      allRecordsComplete: true,
      dumpInProgress: true,
      dumpLoaded: 0,
      dumpTotal: 0,
    );
    await _loadAggregateAndRecords(state.query);
  }

  Future<void> setStates(Set<String> values) async {
    state = state.copyWith(
      query: state.query.copyWith(states: values, page: 0),
    );
    await fetchImpressions();
  }

  Future<void> setFailureReasons(Set<String> values) async {
    state = state.copyWith(
      query: state.query.copyWith(failureReasons: values, page: 0),
    );
    await fetchImpressions();
  }

  Future<void> setScreenFilters({
    required String address,
    required String inventoryGid,
  }) async {
    state = state.copyWith(
      query: state.query.copyWith(
        address: address.trim(),
        inventoryGid: inventoryGid.trim(),
        page: 0,
      ),
    );
    await fetchImpressions();
  }

  Future<void> setPage(int page) async {
    state = state.copyWith(query: state.query.copyWith(page: page));
    state = state.copyWith(impressions: const AsyncValue.loading());

    try {
      final response = await _fetchPage(state.query);
      state = state.copyWith(
        impressions: AsyncValue.data(
          CampaignImpressionsPage.fromJson(
            response.data as Map<String, dynamic>,
          ),
        ),
      );
    } on DioException catch (e, st) {
      final serverDetails = _extractServerDetails(e);
      state = state.copyWith(
        impressions: AsyncValue.error(
          serverDetails == null ? e : Exception(serverDetails),
          st,
        ),
      );
    } catch (e, st) {
      state = state.copyWith(impressions: AsyncValue.error(e, st));
    }
  }

  Future<void> updatePrefs(CampaignAnalyticsDashboardPrefs prefs) async {
    state = state.copyWith(prefs: prefs);
    await _savePrefs(prefs);
  }

  Future<dynamic> _fetchImpressionsWithFallback(
    CampaignAnalyticsQuery query,
  ) async {
    final baseParams = <String, dynamic>{
      'page': query.page,
      'size': query.size,
      'states': query.states.toList(),
      'failureReasonsType': query.failureReasons.toList(),
      'cities': const <int>[],
      'creatives': const <int>[],
      'creativeContents': const <int>[],
      'customerIds': const <int>[],
      'withPlatformFee': false,
      'withShots': false,
      'asc': false,
      'orderBy': 'showTime',
      if (query.address.isNotEmpty) 'address': query.address,
      if (query.inventoryGid.isNotEmpty) 'inventoryGid': query.inventoryGid,
    };

    // Порядок вариантов подобран по факту: локальный ISO-формат (T-разделитель,
    // без смещения таймзоны) — единственный, который бэкенд стабильно
    // принимает в остальных местах приложения (см. _fetchImpressionsRows в
    // service_dashboard_provider.dart), поэтому пробуем его первым, чтобы не
    // тратить round-trip'ы на заведомо отклоняемые варианты и не создавать
    // лишнюю нагрузку на и так нестабильный прокси/бэкенд.
    final attempts = <Map<String, dynamic>>[
      {
        ...baseParams,
        'localStartDate': _formatLocalIsoDateTime(query.start),
        'localEndDate': _formatLocalIsoDateTime(query.end),
      },
      {
        ...baseParams,
        'localStartDate': _formatSpaceDateTime(query.start.toLocal()),
        'localEndDate': _formatSpaceDateTime(query.end.toLocal()),
      },
      {
        ...baseParams,
        'startDate': _formatSpaceDateTime(query.start.toUtc()),
        'endDate': _formatSpaceDateTime(query.end.toUtc()),
      },
      {
        ...baseParams,
        'startDate': query.start.toUtc().toIso8601String(),
        'endDate': query.end.toUtc().toIso8601String(),
      },
      baseParams,
    ];

    DioException? lastError;

    for (final params in attempts) {
      // Повторы на 502/503/504 с растущей паузой: прокси отдаёт 502, когда
      // бэкенд обрывает соединение или не успевает ответить. Это не тот случай,
      // что с таймаутами: 502 — уже завершённый ответ, так что висящих запросов
      // повтор не добавляет. Паузы длиннее прежних 300/600 мс: под нагрузкой
      // бэкенду нужны секунды, а не доли секунды, чтобы разгрузиться.
      const backoff = [
        Duration(milliseconds: 500),
        Duration(milliseconds: 1500),
        Duration(seconds: 4),
      ];
      final maxAttempts = backoff.length + 1;
      for (var attempt = 0; attempt < maxAttempts; attempt++) {
        try {
          return await _client.dio.get(
            '/api/v1.0/clients/campaigns/$campaignId/impressions',
            queryParameters: params,
            options: Options(listFormat: ListFormat.multi),
          );
        } on DioException catch (e) {
          lastError = e;
          final status = e.response?.statusCode ?? 0;
          final isRetryableStatus = status == 502 || status == 503 || status == 504;
          if (isRetryableStatus && attempt < maxAttempts - 1) {
            // Временный сбой прокси/бэкенда — не в формате параметров дело.
            // Таймауты НЕ ретраим здесь — при и так перегруженном бэкенде
            // повтор на каждый подвисший запрос удваивает нагрузку (а
            // _fetchAllRecords и так шлёт страницы пачками по 6 параллельно),
            // что превращает редкие подвисания в стабильный затык.
            await Future<void>.delayed(backoff[attempt]);
            continue;
          }
          if (status == 400) {
            break; // переходим к следующему варианту параметров
          }
          rethrow;
        }
      }
    }

    throw lastError ??
        StateError('Failed to load campaign impressions for $campaignId');
  }

  Future<dynamic> _fetchPage(CampaignAnalyticsQuery query) {
    return _fetchImpressionsWithFallback(query);
  }

  /// Одна страница выгрузки. null — не удалось даже после дробления.
  ///
  /// 502 от прокси на тяжёлой странице означает не «сервер сломался», а «ответ
  /// не успел прийти за отведённое функции время». Повторять такой запрос в том
  /// же виде смысла мало — он снова не успеет. Поэтому упавшую страницу дробим
  /// пополам: страница P размера S — это ровно страницы 2P и 2P+1 размера S/2,
  /// то же множество записей, но каждый запрос вдвое легче.
  Future<List<CampaignImpressionRecord>?> _fetchPageSplitting(
    CampaignAnalyticsQuery baseQuery,
    int pageIndex,
    int size, {
    int depth = 0,
  }) async {
    try {
      final response = await _fetchImpressionsWithFallback(
        baseQuery.copyWith(page: pageIndex, size: size),
      );
      return CampaignImpressionsPage.fromJson(
        response.data as Map<String, dynamic>,
      ).content;
    } catch (e) {
      if (depth >= 2) {
        // ignore: avoid_print
        print('[analytics] страница $pageIndex (по $size) не загрузилась: $e');
        return null;
      }
      final half = size ~/ 2;
      final first = await _fetchPageSplitting(
        baseQuery,
        pageIndex * 2,
        half,
        depth: depth + 1,
      );
      final second = await _fetchPageSplitting(
        baseQuery,
        pageIndex * 2 + 1,
        half,
        depth: depth + 1,
      );
      if (first == null || second == null) return null;
      return [...first, ...second];
    }
  }

  /// Полная выгрузка показов за период.
  ///
  /// [onProgress] получает промежуточные срезы: отчёты наполняются по ходу, а не
  /// после всей выгрузки — на 120 тысячах показов это минуты ожидания пустых
  /// блоков. Вызывается не чаще раза в несколько секунд: пересборка отчётов на
  /// таком объёме сама по себе не бесплатная.
  ///
  /// Возвращает признак полноты. Раньше первая же упавшая пачка обрывала
  /// выгрузку целиком, и весь хвост периода терялся; теперь упавшие страницы
  /// досылаются по одной в конце, и неполным результат считается только если и
  /// это не помогло.
  Future<({List<CampaignImpressionRecord> records, bool complete})>
  _fetchAllRecords(
    CampaignAnalyticsQuery query, {
    void Function(List<CampaignImpressionRecord> records, int total)? onProgress,
  }) async {
    // Первая страница задаёт размер для всей выгрузки. Если на 500 записях она
    // не приходит (именно на ней и валилась вся аналитика с 502), берём мельче:
    // страниц будет больше, зато каждая успевает ответить. Дробить её так же,
    // как остальные, нельзя — из неё же берутся число страниц и общий итог.
    const sizeLadder = [500, 250, 125];
    CampaignImpressionsPage? firstPage;
    var pageSize = sizeLadder.first;
    Object? firstError;
    for (final size in sizeLadder) {
      try {
        final response = await _fetchImpressionsWithFallback(
          query.copyWith(page: 0, size: size),
        );
        firstPage = CampaignImpressionsPage.fromJson(
          response.data as Map<String, dynamic>,
        );
        pageSize = size;
        break;
      } catch (e) {
        firstError = e;
        // ignore: avoid_print
        print('[analytics] первая страница по $size не пришла: $e');
      }
    }
    if (firstPage == null) throw firstError!;

    final baseQuery = query.copyWith(page: 0, size: pageSize);

    // Держим страницы по номерам, а не одним списком: досланная позже страница
    // встаёт на своё место, и порядок записей не зависит от порядка ответов.
    final loaded = <int, List<CampaignImpressionRecord>>{0: firstPage.content};
    final pagesToLoad = firstPage.totalPages;
    final expected = firstPage.totalElements > 0
        ? firstPage.totalElements
        : pagesToLoad * pageSize;

    List<CampaignImpressionRecord> flatten() {
      final keys = loaded.keys.toList()..sort();
      return [for (final key in keys) ...loaded[key]!];
    }

    var lastPublish = DateTime.now();
    void publish({bool force = false}) {
      if (onProgress == null) return;
      final now = DateTime.now();
      if (!force && now.difference(lastPublish) < const Duration(seconds: 4)) {
        return;
      }
      lastPublish = now;
      onProgress(flatten(), expected);
    }

    final failed = <int>[];
    // Пачки параллельных запросов, но с оглядкой: 502 под нагрузкой лечится не
    // повтором, а снижением давления, поэтому после сбоя пачка сужается и
    // расширяется обратно, только если пошло гладко.
    const maxChunk = 6;
    var chunkSize = maxChunk;
    var next = 1;

    while (next < pagesToLoad) {
      final end = min(next + chunkSize, pagesToLoad);
      final results = await Future.wait([
        for (var pageIndex = next; pageIndex < end; pageIndex++)
          _fetchPageSplitting(baseQuery, pageIndex, pageSize),
      ]);

      var failures = 0;
      for (var i = 0; i < results.length; i++) {
        final pageIndex = next + i;
        final records = results[i];
        if (records == null) {
          failed.add(pageIndex);
          failures++;
        } else {
          loaded[pageIndex] = records;
        }
      }
      next = end;

      if (failures > 0) {
        chunkSize = max(2, chunkSize - 2);
        await Future<void>.delayed(const Duration(seconds: 2));
      } else if (chunkSize < maxChunk) {
        chunkSize += 1;
      }

      // Первую пачку отдаём сразу: пусть блоки наполнятся, не дожидаясь конца.
      publish(force: next <= 1 + maxChunk);
    }

    final stillFailed = <int>[];
    for (final pageIndex in failed) {
      // По одной и с паузой: в общей пачке эти страницы падали именно из-за
      // одновременности.
      await Future<void>.delayed(const Duration(milliseconds: 800));
      final records = await _fetchPageSplitting(baseQuery, pageIndex, pageSize);
      if (records == null) {
        stillFailed.add(pageIndex);
      } else {
        loaded[pageIndex] = records;
      }
      publish();
    }

    if (stillFailed.isNotEmpty) {
      // ignore: avoid_print
      print(
        '[analytics] не догрузились страницы $stillFailed — отчёты строятся '
        'по ${flatten().length} записям из $expected',
      );
    }

    publish(force: true);
    return (records: flatten(), complete: stillFailed.isEmpty);
  }

  static String _formatSpaceDateTime(DateTime value) {
    String pad(int n) => n.toString().padLeft(2, '0');
    return '${value.year}-${pad(value.month)}-${pad(value.day)} '
        '${pad(value.hour)}:${pad(value.minute)}:${pad(value.second)}';
  }

  static String _formatLocalIsoDateTime(DateTime value) {
    final local = value.toLocal();
    String pad(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${pad(local.month)}-${pad(local.day)}T'
        '${pad(local.hour)}:${pad(local.minute)}:${pad(local.second)}';
  }

  static String? _extractServerDetails(DioException error) {
    final data = error.response?.data;
    final uri = error.requestOptions.uri.toString();
    final status = error.response?.statusCode;
    final statusMessage = error.response?.statusMessage;
    if (data == null) return null;
    if (data is String && data.trim().isNotEmpty) return data;
    if (data is Map<String, dynamic>) {
      final values = [
        if (status != null)
          'HTTP $status${statusMessage == null ? '' : ' $statusMessage'}',
        'URL: $uri',
        data['message']?.toString(),
        data['error']?.toString(),
        data['details']?.toString(),
      ].where((value) => value != null && value.trim().isNotEmpty).toList();
      if (values.isNotEmpty) {
        return values.join('\n');
      }
    }
    return [
      if (status != null)
        'HTTP $status${statusMessage == null ? '' : ' $statusMessage'}',
      'URL: $uri',
      data.toString(),
    ].join('\n');
  }
}

/// Сколько живёт загруженная аналитика после выхода из карточки кампании.
///
/// Раньше провайдер был чистым autoDispose: закрыл карточку — данные выбросили,
/// вернулся — всё грузится с нуля, включая полную выгрузку показов на минуты.
/// Хранится это в памяти вкладки, а не в кеше браузера: на диск ничего не
/// пишется, при перезагрузке страницы кеш исчезает сам.
const _analyticsCacheTtl = Duration(hours: 2);

/// Сколько кампаний держим одновременно. Полная выгрузка — это десятки тысяч
/// записей на кампанию, и держать их для всех открытых за сессию карточек
/// значит бесконтрольно занимать память вкладки. Самая давняя кампания
/// вытесняется: она всё равно ещё жива, пока открыта на экране, — снятие
/// удержания лишь возвращает ей обычное поведение autoDispose.
const _analyticsCacheLimit = 3;

final _analyticsCacheOrder = <String>[];
final _analyticsCacheLinks = <String, KeepAliveLink>{};

void _rememberAnalyticsCache(String campaignId, KeepAliveLink link) {
  _analyticsCacheLinks[campaignId] = link;
  _analyticsCacheOrder
    ..remove(campaignId)
    ..add(campaignId);
  while (_analyticsCacheOrder.length > _analyticsCacheLimit) {
    final oldest = _analyticsCacheOrder.removeAt(0);
    _analyticsCacheLinks.remove(oldest)?.close();
  }
}

final campaignAnalyticsProvider = StateNotifierProvider.autoDispose
    .family<CampaignAnalyticsController, CampaignAnalyticsState, String>(
      (ref, campaignId) {
        final link = ref.keepAlive();
        final expiry = Timer(_analyticsCacheTtl, link.close);
        _rememberAnalyticsCache(campaignId, link);
        ref.onDispose(() {
          expiry.cancel();
          _analyticsCacheOrder.remove(campaignId);
          _analyticsCacheLinks.remove(campaignId);
        });
        return CampaignAnalyticsController(campaignId);
      },
    );
