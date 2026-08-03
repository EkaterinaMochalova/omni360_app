import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../api/omni360_client.dart';
import '../models/campaign.dart';
import '../utils/broadcast_schedule.dart';

// --- Campaigns list ---

class CampaignsNotifier extends StateNotifier<AsyncValue<List<Campaign>>> {
  final _client = Omni360Client();

  /// Последняя загрузка прошла не полностью: часть страниц не пришла.
  ///
  /// Без этого признака короткий список выглядел как полный, и «нет активных
  /// кампаний» было не отличить от «страница с ними не загрузилась».
  bool incomplete = false;

  CampaignsNotifier() : super(const AsyncValue.loading()) {
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

  /// Одна страница списка с повторами на временных сбоях.
  ///
  /// Возвращает null, если страница так и не пришла: список из-за одной
  /// страницы целиком терять незачем. Ошибки доступа (401/403) прокидываем —
  /// это не временный сбой, и молчать о нём нельзя.
  Future<Response?> _fetchCampaignsPage(int page, int size) async {
    const backoff = [
      Duration(milliseconds: 500),
      Duration(milliseconds: 1500),
      Duration(seconds: 4),
    ];

    for (var attempt = 0; attempt <= backoff.length; attempt++) {
      try {
        return await _client.dio.get(
          '/api/v1.0/clients/campaigns',
          queryParameters: {'page': page, 'size': size},
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

        if (attempt == backoff.length) {
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

  Future<List<Campaign>?> fetch({bool silent = false}) async {
    final previous = state.asData?.value;
    if (!silent || previous == null) {
      state = const AsyncValue.loading();
    }

    try {
      final campaigns = <Campaign>[];
      var pageSize = _pageSizeLadder.first;
      var page = 0;
      var totalPages = 1;
      var complete = true;

      do {
        Response? response;
        // Размер подбираем на первой странице, дальше держим найденный.
        for (final size in page == 0 ? _pageSizeLadder : [pageSize]) {
          response = await _fetchCampaignsPage(page, size);
          if (response != null) {
            pageSize = size;
            break;
          }
        }

        if (response == null) {
          if (campaigns.isEmpty) {
            throw Exception(
              'Бэкенд не отдал список кампаний (502). Обычно это перегрузка — '
              'попробуйте повторить через минуту.',
            );
          }
          // ignore: avoid_print
          print(
            '[campaigns] список неполный: страница $page не пришла, '
            'собрано ${campaigns.length} кампаний',
          );
          complete = false;
          break;
        }

        final data = response.data;
        List<dynamic> chunk;
        if (data is List) {
          chunk = data;
          totalPages = 1; // no pagination info
        } else if (data is Map && data['content'] is List) {
          chunk = data['content'] as List;
          totalPages = (data['totalPages'] as num?)?.toInt() ?? 1;
        } else if (data is Map && data['data'] is List) {
          chunk = data['data'] as List;
          totalPages = (data['totalPages'] as num?)?.toInt() ?? 1;
        } else {
          chunk = [];
          totalPages = 1;
        }

        campaigns.addAll(
          chunk.map((e) => Campaign.fromJson(e as Map<String, dynamic>)),
        );

        // Отдаём по мере готовности: на аккаунтах с сотнями кампаний ждать
        // все страницы, глядя на крутилку, незачем.
        if (!silent) {
          state = AsyncValue.data(List<Campaign>.from(campaigns));
        }
        page++;
      } while (page < totalPages && page < _maxPages);

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
        '(страниц $page из $totalPages по $pageSize, '
        'полностью: $complete) — $byStatus',
      );

      // Неполный список не должен подменять уже показанный полный: иначе
      // кампания, чья страница не пришла, просто исчезает с экрана.
      if (!complete && previous != null && previous.length > campaigns.length) {
        incomplete = true;
        state = AsyncValue.data(previous);
        return previous;
      }

      incomplete = !complete;
      state = AsyncValue.data(campaigns);
      return campaigns;
    } catch (e, st) {
      if (!silent || previous == null) {
        state = AsyncValue.error(e, st);
      }
      return previous;
    }
  }

  Future<void> changeState(String id, String newState) async {
    await _client.dio.post('/api/v1.0/clients/campaigns/$id/state/$newState');
    await fetch(); // refresh list
  }
}

final campaignsProvider =
    StateNotifierProvider<CampaignsNotifier, AsyncValue<List<Campaign>>>(
      (_) => CampaignsNotifier(),
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
