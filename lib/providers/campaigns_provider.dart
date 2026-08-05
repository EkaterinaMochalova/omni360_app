import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../api/omni360_client.dart';
import '../models/campaign.dart';
import '../utils/broadcast_schedule.dart';

// --- Campaigns list ---

/// Совпадает ли кампания с поисковым запросом.
///
/// Одна функция на весь проект: этим же правилом проверяется, понял ли бэкенд
/// параметр поиска (см. [CampaignsNotifier.searchOnServer]), и по нему же
/// фильтруется уже загруженный список. Разойдись они — и «серверный поиск
/// работает» означало бы не то же самое, что видит пользователь.
bool campaignMatchesQuery(Campaign campaign, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  return campaign.name.toLowerCase().contains(q) ||
      (campaign.advertiser?.toLowerCase().contains(q) ?? false) ||
      (campaign.agencyName?.toLowerCase().contains(q) ?? false) ||
      campaign.id.toLowerCase().contains(q);
}

/// Прогресс загрузки списка.
///
/// У master-аккаунта кампании идут десятками страниц, и поиск до конца
/// загрузки видит только загруженное. Без этих цифр экран выглядел так, будто
/// кампании нет вовсе, — а она просто в ещё не пришедшей странице.
class CampaignsLoadProgress {
  final int loaded;

  /// `totalElements` бэкенда — сколько кампаний всего. null, если ответ без
  /// пагинации.
  final int? total;
  final bool loading;

  /// Загрузка прервана (обычно серверным поиском), часть страниц не читалась.
  final bool paused;

  const CampaignsLoadProgress({
    this.loaded = 0,
    this.total,
    this.loading = false,
    this.paused = false,
  });
}

final campaignsLoadProgressProvider = StateProvider<CampaignsLoadProgress>(
  (_) => const CampaignsLoadProgress(),
);

class CampaignsNotifier extends StateNotifier<AsyncValue<List<Campaign>>> {
  final _client = Omni360Client();
  final Ref _ref;

  /// Последняя загрузка прошла не полностью: часть страниц не пришла.
  ///
  /// Без этого признака короткий список выглядел как полный, и «нет активных
  /// кампаний» было не отличить от «страница с ними не загрузилась».
  bool incomplete = false;

  CampaignsNotifier(this._ref) : super(const AsyncValue.loading()) {
    fetch();
  }

  /// Размеры страницы по убыванию. Прокси отдаёт 502, когда страница не
  /// успевает посчитаться за отведённое функции время, а у master-аккаунтов
  /// кампаний на порядок больше, чем у клиентских, — там и 50 за раз бывает
  /// много. Тогда просим меньше: страниц больше, зато они доходят.
  static const _pageSizeLadder = [50, 25, 10];

  /// Предел на число страниц — предохранитель от бесконечного перебора, если
  /// бэкенд отдаст неправдоподобный totalPages.
  static const _maxPages = 300;

  /// Сколько страниц тянем одновременно. Раньше страницы шли строго по одной,
  /// и на аккаунте, который видит все кампании, список набирался минутами.
  /// Больше четырёх этот прокси не переносит — начинаются 502.
  static const _maxConcurrency = 4;

  /// Загруженные страницы по номеру. Нужны, чтобы догружать список с места
  /// остановки, а не с нуля, после того как его прервал поиск.
  final Map<int, List<Campaign>> _pages = {};
  int _pageSize = _pageSizeLadder.first;
  int _totalPages = 1;
  int? _totalElements;

  /// Номер поколения загрузки: увеличивается при новой загрузке и при отмене.
  /// Всё, что вернулось от прошлого поколения, выбрасывается.
  int _generation = 0;

  /// Сколько страниц имеет смысл читать с учётом предохранителя.
  int get _pageLimit => _totalPages < _maxPages ? _totalPages : _maxPages;

  /// Есть ли ещё непрочитанные страницы — от этого зависит, предлагать ли
  /// «догрузить список».
  bool get hasPendingPages => _pages.length < _pageLimit;

  List<Campaign> _flatten() {
    final indexes = _pages.keys.toList()..sort();
    final result = <Campaign>[];
    for (final index in indexes) {
      result.addAll(_pages[index]!);
    }
    return result;
  }

  int get _loadedCount =>
      _pages.values.fold(0, (sum, page) => sum + page.length);

  /// Публикуется только из асинхронных участков: менять другой провайдер в
  /// момент собственного создания Riverpod не разрешает.
  void _setProgress({required bool loading, bool paused = false}) {
    _ref.read(campaignsLoadProgressProvider.notifier).state =
        CampaignsLoadProgress(
          loaded: _loadedCount,
          total: _totalElements,
          loading: loading,
          paused: paused,
        );
  }

  /// Разбор страницы: у эндпоинта три известных формы ответа.
  ({List<Campaign> items, int totalPages, int? totalElements}) _parsePage(
    dynamic data,
  ) {
    List<dynamic> chunk;
    var totalPages = 1;
    int? totalElements;

    if (data is List) {
      chunk = data;
    } else if (data is Map && data['content'] is List) {
      chunk = data['content'] as List;
      totalPages = (data['totalPages'] as num?)?.toInt() ?? 1;
      totalElements = (data['totalElements'] as num?)?.toInt();
    } else if (data is Map && data['data'] is List) {
      chunk = data['data'] as List;
      totalPages = (data['totalPages'] as num?)?.toInt() ?? 1;
      totalElements = (data['totalElements'] as num?)?.toInt();
    } else {
      chunk = const [];
    }

    return (
      items: chunk
          .whereType<Map<String, dynamic>>()
          .map(Campaign.fromJson)
          .toList(),
      totalPages: totalPages,
      totalElements: totalElements,
    );
  }

  /// Одна страница списка с повторами на временных сбоях.
  ///
  /// Возвращает null, если страница так и не пришла: список из-за одной
  /// страницы целиком терять незачем. Ошибки доступа (401/403) прокидываем —
  /// это не временный сбой, и молчать о нём нельзя.
  /// [retries] — сколько раз повторять. Меньше трёх нужно там, где важнее
  /// быстро понять «не выйдет», чем добиться ответа: перебор размеров страницы
  /// и подбор имени параметра поиска. Прокси внутри себя тоже повторяет, так
  /// что каждая наша попытка — это до четырёх обращений к бэкенду, и полный
  /// перебор на лежащем бэкенде занимал минуты.
  Future<Response?> _fetchCampaignsPage(
    int page,
    int size, {
    Map<String, dynamic>? extra,
    int retries = 3,
  }) async {
    const backoff = [
      Duration(milliseconds: 500),
      Duration(milliseconds: 1500),
      Duration(seconds: 4),
    ];
    final maxAttempt = retries < backoff.length ? retries : backoff.length;

    for (var attempt = 0; attempt <= maxAttempt; attempt++) {
      try {
        return await _client.dio.get(
          '/api/v1.0/clients/campaigns',
          queryParameters: {'page': page, 'size': size, ...?extra},
        );
      } on DioException catch (e) {
        final status = e.response?.statusCode ?? 0;
        if (status == 401 || status == 403) rethrow;

        final temporary =
            status == 502 ||
            status == 503 ||
            status == 504 ||
            e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.receiveTimeout;
        if (!temporary) rethrow;

        if (attempt == maxAttempt) {
          // ignore: avoid_print
          print(
            '[campaigns] страница $page (по $size) не пришла: '
            'HTTP $status ${e.type}',
          );
          return null;
        }
        await Future<void>.delayed(backoff[attempt]);
      }
    }
    return null;
  }

  /// Идущая загрузка и время последней полной.
  ///
  /// Фоновая проверка уведомлений раз в пять минут вызывает `fetch(silent:
  /// true)`, и при старте это приходилось ровно на первую загрузку: список
  /// начинал грузиться заново с нуля, а собранные страницы выбрасывались. На
  /// аккаунте, который видит все кампании, это удваивало ожидание.
  Future<List<Campaign>?>? _inFlight;
  DateTime? _completedAt;
  static const _freshFor = Duration(minutes: 2);

  /// Загрузка списка.
  ///
  /// [resume] — продолжить с непрочитанных страниц, не выбрасывая уже
  /// загруженные (список прерывается серверным поиском, чтобы не спорить с ним
  /// за бэкенд).
  Future<List<Campaign>?> fetch({bool silent = false, bool resume = false}) {
    if (silent) {
      final inFlight = _inFlight;
      if (inFlight != null) return inFlight;

      final previous = state.asData?.value;
      final completedAt = _completedAt;
      if (previous != null &&
          !incomplete &&
          completedAt != null &&
          DateTime.now().difference(completedAt) < _freshFor) {
        return Future.value(previous);
      }
    }

    final future = _runFetch(silent: silent, resume: resume);
    _inFlight = future;
    future.whenComplete(() {
      if (_inFlight == future) _inFlight = null;
    });
    return future;
  }

  Future<List<Campaign>?> _runFetch({
    required bool silent,
    required bool resume,
  }) async {
    final generation = ++_generation;
    final previous = state.asData?.value;
    // При догрузке крутилку вместо списка не ставим: список уже на экране, и
    // подменять его на «загрузка» из-за оставшихся страниц незачем.
    if ((!silent && !resume) || previous == null) {
      state = const AsyncValue.loading();
    }
    if (!resume) {
      _pages.clear();
      _totalPages = 1;
      _totalElements = null;
      _pageSize = _pageSizeLadder.first;
    }

    // Отложенно: fetch вызывается из конструктора провайдера, а менять другой
    // провайдер в этот момент Riverpod не разрешает. Микротаска отработает
    // после сборки дерева, но до первого ответа сети.
    Future<void>.microtask(() {
      if (generation == _generation) _setProgress(loading: true);
    });

    try {
      // Первая страница задаёт размер страницы и общее их число.
      if (!_pages.containsKey(0)) {
        Response? first;
        for (final size in _pageSizeLadder) {
          first = await _fetchCampaignsPage(0, size);
          if (generation != _generation) return state.asData?.value;
          if (first != null) {
            _pageSize = size;
            break;
          }
        }
        if (first == null) {
          throw Exception(
            'Бэкенд не отдал список кампаний (502). Обычно это перегрузка — '
            'попробуйте повторить через минуту.',
          );
        }
        final parsed = _parsePage(first.data);
        _pages[0] = parsed.items;
        _totalPages = parsed.totalPages;
        _totalElements = parsed.totalElements;
        if (!silent) state = AsyncValue.data(_flatten());
        _setProgress(loading: true);
      }

      final failed = <int>[];
      var concurrency = _maxConcurrency;
      var next = 1;

      while (next < _pageLimit) {
        final batch = <int>[];
        while (batch.length < concurrency && next < _pageLimit) {
          if (!_pages.containsKey(next)) batch.add(next);
          next++;
        }
        if (batch.isEmpty) continue;

        final responses = await Future.wait(
          batch.map((page) => _fetchCampaignsPage(page, _pageSize)),
        );
        if (generation != _generation) return state.asData?.value;

        var failures = 0;
        for (var i = 0; i < batch.length; i++) {
          final response = responses[i];
          if (response == null) {
            failed.add(batch[i]);
            failures++;
            continue;
          }
          _pages[batch[i]] = _parsePage(response.data).items;
        }

        // Параллельные запросы этот прокси переносит плохо: как только страницы
        // начали падать, сбавляем темп, на чистом проходе — снова ускоряемся.
        if (failures > 0) {
          if (concurrency > 1) concurrency--;
          await Future<void>.delayed(const Duration(seconds: 1));
          if (generation != _generation) return state.asData?.value;
        } else if (concurrency < _maxConcurrency) {
          concurrency++;
        }

        // Отдаём по мере готовности: на аккаунтах с сотнями кампаний ждать
        // все страницы, глядя на крутилку, незачем.
        if (!silent) state = AsyncValue.data(_flatten());
        _setProgress(loading: true);
      }

      // Упавшие страницы добираем по одной: залпом они уже не вышли.
      for (final page in failed.toList()) {
        final response = await _fetchCampaignsPage(page, _pageSize);
        if (generation != _generation) return state.asData?.value;
        if (response == null) continue;
        _pages[page] = _parsePage(response.data).items;
        failed.remove(page);
        if (!silent) state = AsyncValue.data(_flatten());
      }

      final campaigns = _flatten();
      final complete = failed.isEmpty && _pages.length >= _pageLimit;

      // Диагностика: по ней сразу видно, все ли кампании пришли и какие у них
      // статусы — «нет активных» бывает и настоящим ответом бэкенда.
      final byStatus = <String, int>{};
      for (final campaign in campaigns) {
        byStatus[campaign.displayStatus] =
            (byStatus[campaign.displayStatus] ?? 0) + 1;
      }
      // ignore: avoid_print
      print(
        '[campaigns] загружено ${campaigns.length} '
        '(страниц ${_pages.length} из $_totalPages по $_pageSize, '
        'полностью: $complete) — $byStatus',
      );
      if (failed.isNotEmpty) {
        // ignore: avoid_print
        print('[campaigns] не пришли страницы: $failed');
      }

      _setProgress(loading: false);

      // Неполный список не должен подменять уже показанный полный: иначе
      // кампания, чья страница не пришла, просто исчезает с экрана.
      if (!complete && previous != null && previous.length > campaigns.length) {
        incomplete = true;
        state = AsyncValue.data(previous);
        return previous;
      }

      incomplete = !complete;
      if (complete) _completedAt = DateTime.now();
      state = AsyncValue.data(campaigns);
      return campaigns;
    } catch (e, st) {
      if (generation != _generation) return state.asData?.value;
      _setProgress(loading: false);
      if (!silent || previous == null) {
        state = AsyncValue.error(e, st);
      }
      return previous;
    }
  }

  /// Прервать догрузку списка, сохранив уже загруженное.
  ///
  /// Пока показывать нечего, прерывать нельзя: состояние осталось бы навсегда
  /// в `loading`, и экран показывал бы крутилку вместо результатов поиска.
  void cancelLoad() {
    if (state.asData == null) return;
    _generation++;
    _setProgress(loading: false, paused: hasPendingPages);
  }

  /// Догрузить оставшиеся страницы (после того как загрузку прервал поиск).
  Future<void> resumeLoad() => fetch(resume: true).then((_) {});

  /// Кандидаты в имя параметра поиска. Документации по этому эндпоинту нет, а
  /// гадать вслепую в коде дорого: пробуем по очереди и запоминаем сработавший
  /// на всю сессию.
  static const _searchParams = ['search', 'name', 'query', 'q', 'filter'];

  String? _searchParam;
  bool _searchUnsupported = false;

  /// Одна попытка поиска на бэкенде.
  ///
  /// `ignored: true` — параметр бэкенд не понял (вернул обычную первую
  /// страницу). Пустой ответ и сетевая ошибка ничего не доказывают: это
  /// «неизвестно», иначе один запрос без совпадений навсегда выключил бы
  /// серверный поиск.
  Future<({List<Campaign>? items, bool ignored})> _trySearch(
    String param,
    String query,
  ) async {
    try {
      // retries: 1 — это подбор имени параметра вслепую, пяти таких попыток
      // подряд, и на нестабильном бэкенде полный набор повторов (до 4с
      // бэкоффа на каждой) означал до получаса лишней нагрузки на тот же
      // эндпоинт, который и так еле отвечает. Лучше быстро сказать «не
      // получилось» и не топить бэкенд ещё сильнее.
      final response = await _fetchCampaignsPage(
        0,
        50,
        extra: {param: query},
        retries: 1,
      );
      if (response == null) return (items: null, ignored: false);

      final parsed = _parsePage(response.data);
      if (parsed.items.isEmpty) return (items: null, ignored: false);
      if (!parsed.items.every((c) => campaignMatchesQuery(c, query))) {
        return (items: null, ignored: true);
      }

      // Остальные страницы результата — их обычно единицы. Больше пяти не
      // берём: столько уже проще искать уточнённым запросом.
      final items = [...parsed.items];
      final pages = parsed.totalPages < 5 ? parsed.totalPages : 5;
      for (var page = 1; page < pages; page++) {
        final next = await _fetchCampaignsPage(
          page,
          50,
          extra: {param: query},
          retries: 1,
        );
        if (next == null) break;
        items.addAll(_parsePage(next.data).items);
      }
      return (items: items, ignored: false);
    } on DioException catch (e) {
      final status = e.response?.statusCode ?? 0;
      // ignore: avoid_print
      print('[campaigns] поиск через "$param": HTTP $status');
      // 400/404/405/422 — параметр бэкенду не подходит, вывод тот же, что и от
      // проигнорированного. А 401/403 и сетевые сбои про параметр не говорят
      // ничего, и выключать из-за них серверный поиск нельзя.
      return (
        items: null,
        ignored:
            status == 400 || status == 404 || status == 405 || status == 422,
      );
    } catch (e) {
      // ignore: avoid_print
      print('[campaigns] поиск через "$param" сорвался: $e');
      return (items: null, ignored: false);
    }
  }

  /// Поиск кампаний на бэкенде.
  ///
  /// null — искать на бэкенде не получилось (не поддерживает, ошибка сети или
  /// ничего не нашлось); тогда экран ищет по уже загруженному списку.
  Future<List<Campaign>?> searchOnServer(String query) async {
    final trimmed = query.trim();
    if (trimmed.length < 2 || _searchUnsupported) return null;

    // Пока не загрузилась ни одна страница — искать негде и не в чем: поиск
    // на бэкенде тогда только добавляет запросов к тому же эндпоинту, который
    // и так не может отдать первую страницу. Ждём хотя бы её.
    if (state.asData == null) return null;

    if (_searchParam != null) {
      final result = await _trySearch(_searchParam!, trimmed);
      return result.items;
    }

    var allIgnored = true;
    for (final param in _searchParams) {
      final result = await _trySearch(param, trimmed);
      if (result.items != null) {
        _searchParam = param;
        // ignore: avoid_print
        print('[campaigns] серверный поиск работает через параметр "$param"');
        return result.items;
      }
      if (!result.ignored) allIgnored = false;
    }

    if (allIgnored) {
      _searchUnsupported = true;
      // ignore: avoid_print
      print(
        '[campaigns] бэкенд не понимает ни один из параметров поиска '
        '$_searchParams — ищем по загруженному списку',
      );
    }
    return null;
  }

  Future<void> changeState(String id, String newState) async {
    await _client.dio.post('/api/v1.0/clients/campaigns/$id/state/$newState');
    await fetch(); // refresh list
  }
}

final campaignsProvider =
    StateNotifierProvider<CampaignsNotifier, AsyncValue<List<Campaign>>>(
      (ref) => CampaignsNotifier(ref),
    );

// --- Single campaign detail ---

/// Детальный ответ по кампании — единственное место, где он запрашивается.
///
/// Раньше тот же URL независимо тянули ещё расписание и подсчёт фотоотчётов,
/// то есть на каждую карточку списка уходило по три одинаковых запроса. Под
/// нагрузкой часть из них ловила таймаут — отсюда и звёздочки в таблице
/// темпов. Riverpod кеширует результат по id, так что теперь запрос один.
final campaignDetailProvider = FutureProvider.family<Campaign, String>((
  ref,
  id,
) async {
  final response = await _detailGate.run(
    () => Omni360Client().dio.get('/api/v1.0/clients/campaigns/$id'),
  );
  final data = response.data as Map<String, dynamic>;
  final campaign = Campaign.fromJson(data);
  if ((campaign.budget ?? 0) <= 0) {
    // Без бюджета не считается рекомендуемый лимит — печатаем, где его искать.
    // ignore: avoid_print
    print(
      '[DEBUG budget $id] не найден: totalBudget=${data['totalBudget']} '
      'budget=${data['budget']} budgetBuyer=${data['budgetBuyer']} '
      'budgetConfig=${data['budgetConfig']}',
    );
  }
  return campaign;
});

/// Ограничитель одновременных запросов.
///
/// Детальный ответ просит каждая карточка сама, и без ограничителя десяток
/// запросов уходит залпом — часть ловит таймаут. Собирать их в один пакетный
/// запрос — не выход: тогда экран ждёт последнюю кампанию, чтобы показать
/// первую. Здесь запросы остаются независимыми (карточки заполняются по мере
/// готовности), но одновременно летят не больше [limit].
class _RequestGate {
  final int limit;
  int _active = 0;
  final _waiting = <Completer<void>>[];

  _RequestGate(this.limit);

  Future<T> run<T>(Future<T> Function() task) async {
    if (_active >= limit) {
      final waiter = Completer<void>();
      _waiting.add(waiter);
      await waiter.future;
    }
    _active++;
    try {
      return await task();
    } finally {
      _active--;
      if (_waiting.isNotEmpty) _waiting.removeAt(0).complete();
    }
  }
}

final _detailGate = _RequestGate(3);

/// `timeSettings` есть только в детальном ответе, в списочном его нет — но
/// свой запрос здесь больше не делаем: берём уже загруженный и закешированный
/// детальный ответ. Раньше этот провайдер тянул тот же URL отдельно, и вместе
/// с подсчётом фотоотчётов выходило по три одинаковых запроса на кампанию.
///
/// null возвращаем только если детальный ответ не загрузился: пустое
/// расписание — это «ограничений по времени нет», а не «данных нет».
final campaignScheduleProvider =
    FutureProvider.family<BroadcastSchedule?, String>((ref, id) async {
      try {
        final campaign = await ref.watch(campaignDetailProvider(id).future);
        return BroadcastSchedule(campaign.timeSettings ?? const []);
      } catch (e) {
        // ignore: avoid_print
        print('[schedule $id] детальный ответ не загрузился: $e');
        return null;
      }
    });

/// Состав кампании: `inventory.id` → GID, оператор, адрес.
///
/// Нужен, чтобы подписать экраны без фотоотчётов: ответ про фотоотчёты знает
/// только id поверхности. Сначала пробуем достать состав из уже загруженного
/// детального ответа — тогда запросов не будет вовсе. Если сегменты пришли в
/// нём только идентификаторами, добираем их по одному (так же, как это делает
/// сервисный дашборд).
final campaignInventoryProvider =
    FutureProvider.family<Map<int, CampaignInventoryRef>, String>((
      ref,
      id,
    ) async {
      final campaign = await ref.watch(campaignDetailProvider(id).future);
      final collected = <int, CampaignInventoryRef>{...campaign.inventories};
      if (collected.isNotEmpty) return collected;

      for (final segmentId in campaign.segmentIds) {
        try {
          final response = await _detailGate.run(
            () => Omni360Client().dio.get(
              '/api/v1.0/clients/campaigns/$id/segments/$segmentId',
              queryParameters: {'withPlatformFee': false},
            ),
          );
          final data = response.data;
          if (data is Map<String, dynamic>) {
            collected.addAll(CampaignInventoryRef.collectFrom(data));
          }
        } catch (e) {
          // ignore: avoid_print
          print('[inventory $id] сегмент $segmentId не загрузился: $e');
        }
      }
      return collected;
    });

// --- Campaign stats via GET /impression-stats ---

final campaignStatsProvider = FutureProvider.family<CampaignStats, String>((
  ref,
  id,
) async {
  try {
    final response = await Omni360Client().dio.get(
      '/api/v1.0/clients/campaigns/$id/impression-stats',
      queryParameters: {'reqList': '{}'},
    );
    final data = response.data;
    if (data is Map<String, dynamic>) {
      final stats = CampaignStats.fromImpressionStats(data);
      if (stats.factBudget <= 0) {
        // Диагностика: факт по бюджету не нашёлся ни в одном из ожидаемых
        // полей — печатаем, что реально пришло, чтобы не гадать.
        final customer = data['customerStats'];
        // ignore: avoid_print
        print(
          '[impression-stats $id] factBudget=0 '
          'totalBudgetShowed=${data['totalBudgetShowed']} '
          'dailyBudgetShowed=${data['dailyBudgetShowed']} '
          'customerStats=${customer is Map ? customer.keys.toList() : customer} '
          'budgetShowed=${customer is Map ? customer['budgetShowed'] : null} '
          'keys=${data.keys.toList()}',
        );
      }
      return stats;
    }
  } on DioException catch (e) {
    // ignore: avoid_print
    print('[impression-stats] ${e.response?.statusCode}: ${e.response?.data}');
  }
  return CampaignStats.empty();
});

/// Сторона, по которой показы были, а фотоотчёта нет.
///
/// Нужна, чтобы по проценту покрытия можно было сразу перейти к делу: кому из
/// операторов и по каким экранам писать. Раньше видно было только сам процент.
///
/// Полей GID, адреса, оператора и города в ответе `impression-inventory-stats`
/// нет вообще: там про поверхность известны только `inventory.id` и внутреннее
/// имя вида `Estetika_5th_Saratov_Sokolovaya/Tankistov`. Поэтому здесь лежит
/// только [inventoryId] — ключ, по которому подписи берутся из выгрузки
/// показов, где есть и GID, и адрес, и оператор.
class PhotoMissingSide {
  final int? inventoryId;

  /// Внутреннее имя поверхности — то, что реально отдаёт этот эндпоинт.
  final String name;
  final int shows;

  const PhotoMissingSide({
    required this.inventoryId,
    required this.name,
    required this.shows,
  });
}

class CampaignPhotoCoverage {
  final int totalSides;
  final int sidesWithPhoto;

  /// Стороны без фотоотчёта — по убыванию числа показов: сверху то, что дороже
  /// всего осталось без подтверждения.
  final List<PhotoMissingSide> missing;

  const CampaignPhotoCoverage({
    required this.totalSides,
    required this.sidesWithPhoto,
    this.missing = const [],
  });

  double get percent =>
      totalSides > 0 ? (sidesWithPhoto / totalSides) * 100 : 0.0;

  /// Сколько всего показов прошло на экранах без фотоотчёта.
  int get missingShows =>
      missing.fold(0, (sum, side) => sum + side.shows);
}

final campaignPhotoCoverageProvider =
    FutureProvider.family<CampaignPhotoCoverage, String>((ref, id) async {
      final client = Omni360Client().dio;

      // Даты берём из уже загруженного детального ответа, а не запрашиваем его
      // повторно: тот же URL до этого тянули и здесь, и в расписании.
      final detail = await ref.watch(campaignDetailProvider(id).future);

      String? toApiDateTime(String? date, {required bool endOfDay}) {
        if (date == null || date.isEmpty) return null;
        final trimmed = date.trim();
        if (trimmed.contains('T')) return trimmed;
        return '${trimmed}T${endOfDay ? '23:59:59' : '00:00:00'}';
      }

      final startDate = toApiDateTime(detail.startDate, endOfDay: false);
      final endDate = toApiDateTime(detail.endDate, endOfDay: true);

      final rows = <Map<String, dynamic>>[];
      const size = 500;
      const maxPages = 20;
      const waveSize = 3;

      Future<List<Map<String, dynamic>>?> fetchPage(int page) async {
        final params = <String, dynamic>{
          'page': page,
          'size': size,
          'localStartDate': startDate,
          'localEndDate': endDate,
        }..removeWhere((_, value) => value == null);
        final resp = await client.get(
          '/api/v1.0/clients/campaigns/$id/impression-inventory-stats',
          queryParameters: params,
          options: Options(listFormat: ListFormat.multi),
        );
        final data = resp.data;
        if (data is! List) return null;
        return data.whereType<Map<String, dynamic>>().toList();
      }

      // Страницы неизвестного общего числа — берём их волнами по несколько
      // штук параллельно вместо строго последовательного перебора: тяжёлые
      // кампании иначе накапливают задержку до 20 круговых обращений подряд
      // и упираются в клиентский таймаут, хотя сам бэкенд не перегружен.
      var page = 0;
      var reachedEnd = false;
      while (!reachedEnd && page < maxPages) {
        final wavePages = [
          for (var i = 0; i < waveSize && page + i < maxPages; i++) page + i,
        ];
        final waveResults = await Future.wait(wavePages.map(fetchPage));
        for (final chunk in waveResults) {
          if (chunk == null || chunk.isEmpty) {
            reachedEnd = true;
            break;
          }
          rows.addAll(chunk);
          if (chunk.length < size) {
            reachedEnd = true;
            break;
          }
        }
        page += wavePages.length;
      }

      String sideKeyFromRow(Map<String, dynamic> row) {
        final inv = row['inventory'];
        final invId = (inv is Map ? (inv['id'] as num?)?.toInt() : null);
        final invName = inv is Map ? inv['name']?.toString() : null;
        final side = row['side']?.toString();
        if (invId != null) return 'id:$invId';
        if ((invName ?? '').isNotEmpty || (side ?? '').isNotEmpty) {
          return 'gid:${invName ?? ''}|side:${side ?? ''}';
        }
        return '';
      }

      bool hasShows(Map<String, dynamic> row) {
        final showed = (row['totalShowed'] as num?)?.toInt() ?? 0;
        final budget = (row['totalShowedBudget'] as num?)?.toDouble() ?? 0;
        return showed > 0 || budget > 0;
      }

      final sidesWithShows = <String>{};
      final withPhotoKeys = <String>{};
      final sideInfo = <String, PhotoMissingSide>{};
      for (final row in rows) {
        if (!hasShows(row)) continue;
        final sideKey = sideKeyFromRow(row);
        if (sideKey.isEmpty) continue;
        sidesWithShows.add(sideKey);

        final inventory = row['inventory'];
        final shows = (row['totalShowed'] as num?)?.toInt() ?? 0;
        final known = sideInfo[sideKey];
        sideInfo[sideKey] = PhotoMissingSide(
          inventoryId: inventory is Map
              ? (inventory['id'] as num?)?.toInt()
              : null,
          name: (inventory is Map ? inventory['name']?.toString() : null) ?? '',
          // Одна сторона может прийти несколькими строками (разные креативы,
          // дни) — показы складываем.
          shows: (known?.shows ?? 0) + shows,
        );

        final shotCount = (row['shotCount'] as num?)?.toInt() ?? 0;
        if (shotCount <= 0) continue;
        withPhotoKeys.add(sideKey);
      }

      final totalSides = sidesWithShows.length;
      final sidesWithPhoto = withPhotoKeys.length;

      final missing =
          sidesWithShows
              .where((key) => !withPhotoKeys.contains(key))
              .map((key) => sideInfo[key])
              .whereType<PhotoMissingSide>()
              .toList()
            ..sort((a, b) => b.shows.compareTo(a.shows));

      return CampaignPhotoCoverage(
        totalSides: totalSides,
        sidesWithPhoto: sidesWithPhoto > totalSides && totalSides > 0
            ? totalSides
            : sidesWithPhoto,
        missing: missing,
      );
    });
