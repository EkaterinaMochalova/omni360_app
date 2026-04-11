import 'dart:convert';

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
  final int page;
  final int size;

  const CampaignAnalyticsQuery({
    required this.start,
    required this.end,
    required this.states,
    required this.failureReasons,
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
      page: 0,
      size: 50,
    );
  }

  CampaignAnalyticsQuery copyWith({
    DateTime? start,
    DateTime? end,
    Set<String>? states,
    Set<String>? failureReasons,
    int? page,
    int? size,
  }) {
    return CampaignAnalyticsQuery(
      start: start ?? this.start,
      end: end ?? this.end,
      states: states ?? this.states,
      failureReasons: failureReasons ?? this.failureReasons,
      page: page ?? this.page,
      size: size ?? this.size,
    );
  }
}

class CampaignAnalyticsState {
  final AsyncValue<CampaignImpressionsPage> impressions;
  final AsyncValue<CampaignAnalyticsFiltersData> filters;
  final CampaignAnalyticsDashboardPrefs prefs;
  final CampaignAnalyticsQuery query;

  const CampaignAnalyticsState({
    required this.impressions,
    required this.filters,
    required this.prefs,
    required this.query,
  });

  factory CampaignAnalyticsState.initial() => CampaignAnalyticsState(
    impressions: const AsyncValue.loading(),
    filters: const AsyncValue.loading(),
    prefs: const CampaignAnalyticsDashboardPrefs.defaults(),
    query: CampaignAnalyticsQuery.initial(),
  );

  CampaignAnalyticsState copyWith({
    AsyncValue<CampaignImpressionsPage>? impressions,
    AsyncValue<CampaignAnalyticsFiltersData>? filters,
    CampaignAnalyticsDashboardPrefs? prefs,
    CampaignAnalyticsQuery? query,
  }) {
    return CampaignAnalyticsState(
      impressions: impressions ?? this.impressions,
      filters: filters ?? this.filters,
      prefs: prefs ?? this.prefs,
      query: query ?? this.query,
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
    state = state.copyWith(impressions: const AsyncValue.loading());

    try {
      final query = state.query;
      final response = await _fetchImpressionsWithFallback(query);

      state = state.copyWith(
        impressions: AsyncValue.data(
          CampaignImpressionsPage.fromJson(
            response.data as Map<String, dynamic>,
          ),
        ),
      );
    } catch (e, st) {
      state = state.copyWith(impressions: AsyncValue.error(e, st));
    }
  }

  Future<void> setRange(DateTime start, DateTime end) async {
    state = state.copyWith(
      query: state.query.copyWith(start: start, end: end, page: 0),
    );
    await fetchImpressions();
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

  Future<void> setPage(int page) async {
    state = state.copyWith(query: state.query.copyWith(page: page));
    await fetchImpressions();
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
      if (query.states.isNotEmpty) 'states': query.states.toList(),
      if (query.failureReasons.isNotEmpty)
        'failureReasonsType': query.failureReasons.toList(),
    };

    final attempts = <Map<String, dynamic>>[
      {
        ...baseParams,
        'localStartDate': _formatLocalDateTime(query.start),
        'localEndDate': _formatLocalDateTime(query.end),
      },
      {
        ...baseParams,
        'startDate': query.start.toUtc().toIso8601String(),
        'endDate': query.end.toUtc().toIso8601String(),
      },
      baseParams,
    ];

    DioException? lastBadRequest;

    for (final params in attempts) {
      try {
        return await _client.dio.get(
          '/api/v1.0/clients/campaigns/$campaignId/impressions',
          queryParameters: params,
          options: Options(listFormat: ListFormat.multi),
        );
      } on DioException catch (e) {
        if (e.response?.statusCode == 400) {
          lastBadRequest = e;
          continue;
        }
        rethrow;
      }
    }

    throw lastBadRequest ??
        StateError('Failed to load campaign impressions for $campaignId');
  }

  static String _formatLocalDateTime(DateTime value) {
    final local = value.toLocal();
    String pad(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${pad(local.month)}-${pad(local.day)}T'
        '${pad(local.hour)}:${pad(local.minute)}:${pad(local.second)}';
  }
}

final campaignAnalyticsProvider = StateNotifierProvider.autoDispose
    .family<CampaignAnalyticsController, CampaignAnalyticsState, String>(
      (ref, campaignId) => CampaignAnalyticsController(campaignId),
    );
