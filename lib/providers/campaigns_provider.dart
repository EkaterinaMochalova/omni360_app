import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../api/omni360_client.dart';
import '../models/campaign.dart';
import '../utils/broadcast_schedule.dart';

// --- Campaigns list ---

class CampaignsNotifier extends StateNotifier<AsyncValue<List<Campaign>>> {
  final _client = Omni360Client();

  CampaignsNotifier() : super(const AsyncValue.loading()) {
    fetch();
  }

  Future<List<Campaign>?> fetch({bool silent = false}) async {
    final previous = state.asData?.value;
    if (!silent || previous == null) {
      state = const AsyncValue.loading();
    }

    try {
      final all = <dynamic>[];
      int page = 0;
      const pageSize = 50;
      int totalPages = 1;

      do {
        final response = await _client.dio.get(
          '/api/v1.0/clients/campaigns',
          queryParameters: {'page': page, 'size': pageSize},
        );
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

        all.addAll(chunk);
        page++;
      } while (page < totalPages);
      final campaigns = all
          .map((e) => Campaign.fromJson(e as Map<String, dynamic>))
          .toList();
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
class PhotoMissingSide {
  final String gid;
  final String side;
  final String operatorName;
  final String city;
  final int shows;

  const PhotoMissingSide({
    required this.gid,
    required this.side,
    required this.operatorName,
    required this.city,
    required this.shows,
  });

  /// GID со стороной, если сторона известна отдельным полем.
  String get label => side.isEmpty ? gid : '$gid $side';
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

      // Имя оператора/города бэкенд отдаёт то строкой, то вложенным объектом, и
      // ключ в этом ответе заранее не известен — перебираем варианты, а не
      // жёстко один. Пустая строка вместо срыва: список GID полезен и без
      // оператора.
      String? nameOf(dynamic node) {
        if (node is String) return node.trim().isEmpty ? null : node.trim();
        if (node is Map) {
          final name = node['name'] ?? node['title'] ?? node['shortName'];
          final text = name?.toString().trim();
          if (text != null && text.isNotEmpty) return text;
        }
        return null;
      }

      String pickName(Map<String, dynamic> row, List<String> keys) {
        for (final key in keys) {
          final value = nameOf(row[key]);
          if (value != null) return value;
        }
        final inventory = row['inventory'];
        if (inventory is Map) {
          for (final key in keys) {
            final value = nameOf(inventory[key]);
            if (value != null) return value;
          }
        }
        return '';
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
        final gid =
            (inventory is Map ? inventory['name']?.toString() : null) ??
            row['inventoryGid']?.toString() ??
            sideKey;
        final shows = (row['totalShowed'] as num?)?.toInt() ?? 0;
        final known = sideInfo[sideKey];
        sideInfo[sideKey] = PhotoMissingSide(
          gid: gid,
          side: row['side']?.toString() ?? '',
          operatorName: pickName(row, const [
            'displayOwnerDTO',
            'displayOwner',
            'displayOwnerName',
            'operator',
            'owner',
          ]),
          city: pickName(row, const ['city', 'cityName', 'cityDTO']),
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

      if (missing.isNotEmpty && missing.first.operatorName.isEmpty) {
        // Диагностика: имя оператора не нашлось ни под одним из ожидаемых
        // ключей — печатаем, что реально пришло, чтобы не угадывать.
        // ignore: avoid_print
        print(
          '[photo-coverage $id] оператор не найден, ключи строки: '
          '${rows.isEmpty ? '—' : rows.first.keys.toList()}',
        );
      }

      return CampaignPhotoCoverage(
        totalSides: totalSides,
        sidesWithPhoto: sidesWithPhoto > totalSides && totalSides > 0
            ? totalSides
            : sidesWithPhoto,
        missing: missing,
      );
    });
