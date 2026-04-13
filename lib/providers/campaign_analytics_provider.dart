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

  const CampaignAnalyticsState({
    required this.impressions,
    required this.aggregate,
    required this.filters,
    required this.prefs,
    required this.query,
  });

  factory CampaignAnalyticsState.initial() => CampaignAnalyticsState(
    impressions: const AsyncValue.loading(),
    aggregate: const AsyncValue.loading(),
    filters: const AsyncValue.loading(),
    prefs: const CampaignAnalyticsDashboardPrefs.defaults(),
    query: CampaignAnalyticsQuery.initial(),
  );

  CampaignAnalyticsState copyWith({
    AsyncValue<CampaignImpressionsPage>? impressions,
    AsyncValue<CampaignAnalyticsAggregate>? aggregate,
    AsyncValue<CampaignAnalyticsFiltersData>? filters,
    CampaignAnalyticsDashboardPrefs? prefs,
    CampaignAnalyticsQuery? query,
  }) {
    return CampaignAnalyticsState(
      impressions: impressions ?? this.impressions,
      aggregate: aggregate ?? this.aggregate,
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
    state = state.copyWith(
      impressions: const AsyncValue.loading(),
      aggregate: const AsyncValue.loading(),
    );

    try {
      final query = state.query;
      final results = await Future.wait([
        _fetchImpressionsWithFallback(query),
        _fetchAggregate(query),
      ]);
      final response = results[0];
      final aggregate = results[1] as CampaignAnalyticsAggregate;

      state = state.copyWith(
        impressions: AsyncValue.data(
          CampaignImpressionsPage.fromJson(
            response.data as Map<String, dynamic>,
          ),
        ),
        aggregate: AsyncValue.data(aggregate),
      );
    } on DioException catch (e, st) {
      final serverDetails = _extractServerDetails(e);
      state = state.copyWith(
        impressions: AsyncValue.error(
          serverDetails == null ? e : Exception(serverDetails),
          st,
        ),
        aggregate: AsyncValue.error(
          serverDetails == null ? e : Exception(serverDetails),
          st,
        ),
      );
    } catch (e, st) {
      state = state.copyWith(
        impressions: AsyncValue.error(e, st),
        aggregate: AsyncValue.error(e, st),
      );
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

    final attempts = <Map<String, dynamic>>[
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
        'localStartDate': _formatLocalIsoDateTime(query.start),
        'localEndDate': _formatLocalIsoDateTime(query.end),
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

  Future<CampaignAnalyticsAggregate> _fetchAggregate(
    CampaignAnalyticsQuery query,
  ) async {
    final aggregateQuery = query.copyWith(page: 0, size: 500);
    final allRecords = <CampaignImpressionRecord>[];

    while (true) {
      final response = await _fetchImpressionsWithFallback(aggregateQuery.copyWith(page: allRecords.length ~/ 500));
      final page = CampaignImpressionsPage.fromJson(
        response.data as Map<String, dynamic>,
      );
      allRecords.addAll(page.content);
      if (page.last) break;
    }

    return CampaignAnalyticsAggregate.fromRecords(allRecords);
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

final campaignAnalyticsProvider = StateNotifierProvider.autoDispose
    .family<CampaignAnalyticsController, CampaignAnalyticsState, String>(
      (ref, campaignId) => CampaignAnalyticsController(campaignId),
    );
