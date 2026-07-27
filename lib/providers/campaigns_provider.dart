import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../api/omni360_client.dart';
import '../models/campaign.dart';

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

final campaignDetailProvider = FutureProvider.family<Campaign, String>((
  ref,
  id,
) async {
  final response = await Omni360Client().dio.get(
    '/api/v1.0/clients/campaigns/$id',
  );
  final data = response.data as Map<String, dynamic>;
  // ignore: avoid_print
  print(
    '[DEBUG detail] budgetBuyer=${data['budgetBuyer']} totalBudget=${data['totalBudget']}',
  );
  // ignore: avoid_print
  print(
    '[DEBUG detail] maxImpressionsCount=${data['maxImpressionsCount']} maxDailyImpressionsCount=${data['maxDailyImpressionsCount']}',
  );
  // ignore: avoid_print
  print(
    '[DEBUG detail] strategy=${data['strategy']} segments=${data['segments']}',
  );
  final campaign = Campaign.fromJson(data);
  // Плановый OTS кампании берётся первым делом из maxImpressionsCount —
  // печатаем всех кандидатов рядом с результатом, чтобы проверить, что это
  // действительно контакты, а не лимит выходов, и что единицы совпадают
  // с суммой по сегментам (та домножается на 1000).
  // ignore: avoid_print
  print(
    '[DEBUG ots plan] parsed=${campaign.ots} exits=${campaign.exits} | '
    'maxImpressionsCount=${data['maxImpressionsCount']} '
    'ots=${data['ots']} totalOts=${data['totalOts']} '
    'maxDailyImpressionsCount=${data['maxDailyImpressionsCount']} '
    'plays=${data['plays']} exits=${data['exits']}',
  );
  return campaign;
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
      // Диагностика OTS: сверяем, из какого поля пришли план и факт и не
      // расходятся ли они на порядок (признак разных единиц — контакты против
      // тысяч контактов, либо выходы, подставленные вместо контактов).
      // ignore: avoid_print
      print(
        '[ots $id] plan=${stats.planOts} fact=${stats.factOts} '
        'estimated=${stats.factOtsIsEstimated} | '
        'otsCount=${data['otsCount']} reservedOts=${(data['reservedBudgetStat'] as Map?)?['ots']} '
        'otsCountShowed=${data['otsCountShowed']} totalDmpOts=${data['totalDmpOts']} '
        'totalEstimatedOts=${data['totalEstimatedOts']} '
        'hourlyOts=${data['hourlyOts']} hourlyOtsShowed=${data['hourlyOtsShowed']} '
        'totalCountShowed=${data['totalCountShowed']}',
      );
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

class CampaignPhotoCoverage {
  final int totalSides;
  final int sidesWithPhoto;

  const CampaignPhotoCoverage({
    required this.totalSides,
    required this.sidesWithPhoto,
  });

  double get percent =>
      totalSides > 0 ? (sidesWithPhoto / totalSides) * 100 : 0.0;
}

final campaignPhotoCoverageProvider =
    FutureProvider.family<CampaignPhotoCoverage, String>((ref, id) async {
      final client = Omni360Client().dio;

      final detailResp = await client.get('/api/v1.0/clients/campaigns/$id');
      final detail = detailResp.data;
      if (detail is! Map<String, dynamic>) {
        return const CampaignPhotoCoverage(totalSides: 0, sidesWithPhoto: 0);
      }

      String? toApiDateTime(String? date, {required bool endOfDay}) {
        if (date == null || date.isEmpty) return null;
        final trimmed = date.trim();
        if (trimmed.contains('T')) return trimmed;
        return '${trimmed}T${endOfDay ? '23:59:59' : '00:00:00'}';
      }

      final startDate = toApiDateTime(
        detail['startDate']?.toString(),
        endOfDay: false,
      );
      final endDate = toApiDateTime(
        detail['endDate']?.toString(),
        endOfDay: true,
      );

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
      for (final row in rows) {
        if (!hasShows(row)) continue;
        final sideKey = sideKeyFromRow(row);
        if (sideKey.isEmpty) continue;
        sidesWithShows.add(sideKey);

        final shotCount = (row['shotCount'] as num?)?.toInt() ?? 0;
        if (shotCount <= 0) continue;
        withPhotoKeys.add(sideKey);
      }

      final totalSides = sidesWithShows.length;
      final sidesWithPhoto = withPhotoKeys.length;

      return CampaignPhotoCoverage(
        totalSides: totalSides,
        sidesWithPhoto: sidesWithPhoto > totalSides && totalSides > 0
            ? totalSides
            : sidesWithPhoto,
      );
    });
