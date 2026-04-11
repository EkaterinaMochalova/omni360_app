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
