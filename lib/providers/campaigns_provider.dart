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
  return Campaign.fromJson(data);
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
      return CampaignStats.fromImpressionStats(data);
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

      final segmentIds = (detail['segments'] as List? ?? const [])
          .map((s) => ((s as Map?)?['id'] as num?)?.toInt())
          .whereType<int>()
          .toList();

      final sideKeys = <String>{};
      for (final segmentId in segmentIds) {
        try {
          final segResp = await client.get(
            '/api/v1.0/clients/campaigns/$id/segments/$segmentId',
            queryParameters: {'withPlatformFee': false},
          );
          final segData = segResp.data;
          if (segData is! Map<String, dynamic>) continue;
          final inventories = (segData['inventories'] as List? ?? const [])
              .whereType<Map<String, dynamic>>();
          for (final inv in inventories) {
            final invId = (inv['id'] as num?)?.toInt();
            final gid = inv['gid']?.toString();
            final side = inv['side']?.toString();
            final key = invId != null
                ? 'id:$invId'
                : 'gid:${gid ?? ''}|side:${side ?? ''}';
            if (key != 'gid:|side:') {
              sideKeys.add(key);
            }
          }
        } catch (_) {
          // ignore segment errors, continue with remaining segments
        }
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
      var page = 0;
      const size = 500;
      while (true) {
        final params = <String, dynamic>{
          'page': page,
          'size': size,
          'withShots': true,
          if (startDate != null) 'localStartDate': startDate,
          if (endDate != null) 'localEndDate': endDate,
        };
        final resp = await client.get(
          '/api/v1.0/clients/campaigns/$id/impression-inventory-stats',
          queryParameters: params,
          options: Options(listFormat: ListFormat.multi),
        );
        final data = resp.data;
        if (data is! List) break;
        final chunk = data.whereType<Map<String, dynamic>>().toList();
        if (chunk.isEmpty) break;
        rows.addAll(chunk);
        if (chunk.length < size) break;
        page++;
        if (page >= 20) break;
      }

      final withPhotoKeys = <String>{};
      for (final row in rows) {
        final shotCount = (row['shotCount'] as num?)?.toInt() ?? 0;
        if (shotCount <= 0) continue;
        final inv = row['inventory'];
        final invId = (inv is Map ? (inv['id'] as num?)?.toInt() : null);
        final invName = inv is Map ? inv['name']?.toString() : null;
        final side = row['side']?.toString();
        final key = invId != null
            ? 'id:$invId'
            : 'gid:${invName ?? ''}|side:${side ?? ''}';
        if (key != 'gid:|side:') {
          withPhotoKeys.add(key);
        }
      }

      final totalSides = sideKeys.isNotEmpty ? sideKeys.length : rows.length;
      final sidesWithPhoto = withPhotoKeys.length;

      return CampaignPhotoCoverage(
        totalSides: totalSides,
        sidesWithPhoto: sidesWithPhoto > totalSides && totalSides > 0
            ? totalSides
            : sidesWithPhoto,
      );
    });
