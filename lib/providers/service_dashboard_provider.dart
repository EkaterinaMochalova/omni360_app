import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/omni360_client.dart';
import '../models/campaign.dart';
import '../models/service_dashboard.dart';
import 'campaigns_provider.dart';

class ServiceDashboardState {
  final AsyncValue<List<Campaign>> campaigns;
  final AsyncValue<List<ServiceDashboardCampaignSummary>> summaries;
  final ServiceDashboardQuery query;
  final ServiceDashboardFiltersData filters;

  const ServiceDashboardState({
    required this.campaigns,
    required this.summaries,
    required this.query,
    required this.filters,
  });

  factory ServiceDashboardState.initial() => ServiceDashboardState(
    campaigns: const AsyncValue.loading(),
    summaries: const AsyncValue.loading(),
    query: ServiceDashboardQuery.initial(),
    filters: const ServiceDashboardFiltersData(
      brands: [],
      advertisers: [],
      operators: [],
      cities: [],
      formats: [],
      operatorIds: {},
      cityIds: {},
    ),
  );

  ServiceDashboardState copyWith({
    AsyncValue<List<Campaign>>? campaigns,
    AsyncValue<List<ServiceDashboardCampaignSummary>>? summaries,
    ServiceDashboardQuery? query,
    ServiceDashboardFiltersData? filters,
  }) {
    return ServiceDashboardState(
      campaigns: campaigns ?? this.campaigns,
      summaries: summaries ?? this.summaries,
      query: query ?? this.query,
      filters: filters ?? this.filters,
    );
  }
}

class ServiceDashboardController extends StateNotifier<ServiceDashboardState> {
  ServiceDashboardController(this._ref)
    : _client = Omni360Client(),
      super(ServiceDashboardState.initial()) {
    _load();
  }

  final Ref _ref;
  final Omni360Client _client;

  Future<void> _load() async {
    await _loadCampaigns();
    await refresh();
  }

  Future<void> _loadCampaigns() async {
    try {
      final campaigns =
          await _ref.read(campaignsProvider.notifier).fetch(silent: true) ??
          const <Campaign>[];
      final extraFilters = await _loadReferenceFilters();
      state = state.copyWith(
        campaigns: AsyncValue.data(campaigns),
        filters: _buildFilters(campaigns, extraFilters: extraFilters),
      );
    } catch (e, st) {
      state = state.copyWith(campaigns: AsyncValue.error(e, st));
    }
  }

  Future<void> refresh() async {
    final campaigns = state.campaigns.asData?.value;
    if (campaigns == null) return;

    state = state.copyWith(summaries: const AsyncValue.loading());
    try {
      final filteredCampaigns = filterCampaigns(campaigns, state.query);
      if (filteredCampaigns.isEmpty) {
        state = state.copyWith(summaries: const AsyncValue.data([]));
        return;
      }

      final summaries = await _fetchCampaignStats(
        filteredCampaigns,
        state.query,
        state.filters,
      );

      state = state.copyWith(summaries: AsyncValue.data(summaries));
    } catch (e, st) {
      state = state.copyWith(summaries: AsyncValue.error(e, st));
    }
  }

  Future<List<ServiceDashboardCampaignSummary>> _fetchCampaignStats(
    List<Campaign> campaigns,
    ServiceDashboardQuery query,
    ServiceDashboardFiltersData filters,
  ) async {
    const chunkSize = 40;
    final chunkFutures = <Future<List<ServiceDashboardCampaignSummary>>>[];

    for (var i = 0; i < campaigns.length; i += chunkSize) {
      final chunk = campaigns.skip(i).take(chunkSize).toList();
      chunkFutures.add(_fetchStatsForCampaignChunk(chunk, query, filters));
    }

    final chunkResults = await Future.wait(chunkFutures);
    return chunkResults.expand((items) => items).toList();
  }

  Future<List<ServiceDashboardCampaignSummary>> _fetchStatsForCampaignChunk(
    List<Campaign> campaigns,
    ServiceDashboardQuery query,
    ServiceDashboardFiltersData filters,
  ) async {
    final campaignIds = campaigns
        .map((campaign) => int.tryParse(campaign.id))
        .whereType<int>()
        .toList();
    if (campaignIds.isEmpty) return const [];

    try {
      return await _fetchStatsChunk(campaignIds, query, filters);
    } on DioException catch (e) {
      final status = e.response?.statusCode ?? 0;
      if (status < 500) rethrow;

      if (campaigns.length == 1) {
        return [ServiceDashboardCampaignSummary.fromCampaign(campaigns.first)];
      }

      final middle = campaigns.length ~/ 2;
      final left = campaigns.sublist(0, middle);
      final right = campaigns.sublist(middle);
      final parts = await Future.wait([
        _fetchStatsForCampaignChunk(left, query, filters),
        _fetchStatsForCampaignChunk(right, query, filters),
      ]);
      return parts.expand((items) => items).toList();
    }
  }

  Future<List<ServiceDashboardCampaignSummary>> _fetchStatsChunk(
    List<int> campaignIds,
    ServiceDashboardQuery query,
    ServiceDashboardFiltersData filters,
  ) async {
    final reqList = <String, dynamic>{
      'campaignIds': campaignIds,
      'startDate': _formatSpaceDateTime(query.start.toUtc()),
      'endDate': _formatSpaceDateTime(query.end.toUtc()),
      'cities': const <int>[],
      'displayOwnerIds': const <int>[],
      'creatives': const <int>[],
      'creativeContents': const <int>[],
      'states': const <String>[],
      'groupMode': 'SUMMARY',
      'page': 0,
      'size': campaignIds.length,
      'priceMode': 'CUSTOMER_CHARGE_INCLUDED',
      'withPlatformFee': false,
    };

    final response = await _client.dio.get(
      '/api/v1.0/clients/impressions/campaigns-stats',
      queryParameters: {'reqList': jsonEncode(reqList)},
      options: Options(listFormat: ListFormat.multi),
    );

    return (response.data as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(ServiceDashboardCampaignSummary.fromJson)
        .toList();
  }

  Future<void> setRange(DateTime start, DateTime end) async {
    state = state.copyWith(
      query: state.query.copyWith(start: start, end: end),
    );
    await refresh();
  }

  Future<void> updateFilters({
    String? campaignSearch,
    Set<String>? brands,
    Set<String>? advertisers,
    Set<String>? operators,
    Set<String>? cities,
    Set<String>? formats,
  }) async {
    state = state.copyWith(
      query: state.query.copyWith(
        campaignSearch: campaignSearch,
        brands: brands,
        advertisers: advertisers,
        operators: operators,
        cities: cities,
        formats: formats,
      ),
    );
    await refresh();
  }

  static List<Campaign> filterCampaigns(
    List<Campaign> campaigns,
    ServiceDashboardQuery query,
  ) {
    final search = query.campaignSearch.trim().toLowerCase();

    return campaigns.where((campaign) {
      final matchesSearch =
          search.isEmpty || campaign.name.toLowerCase().contains(search);
      final matchesBrand =
          query.brands.isEmpty ||
          (campaign.brandName != null &&
              query.brands.contains(campaign.brandName));
      final matchesAdvertiser =
          query.advertisers.isEmpty ||
          (campaign.customerName != null &&
              query.advertisers.contains(campaign.customerName));
      final matchesOperator =
          query.operators.isEmpty ||
          campaign.displayOwners.any(query.operators.contains);
      final matchesCity =
          query.cities.isEmpty ||
          (campaign.city != null && query.cities.contains(campaign.city));
      final matchesFormat =
          query.formats.isEmpty || campaign.formats.any(query.formats.contains);

      return matchesSearch &&
          matchesBrand &&
          matchesAdvertiser &&
          matchesOperator &&
          matchesCity &&
          matchesFormat;
    }).toList();
  }

  Future<ServiceDashboardFiltersData> _loadReferenceFilters() async {
    try {
      final responses = await Future.wait([
        _client.dio.get(
          '/api/v1.0/clients/regions',
          queryParameters: {'page': 0, 'size': 500},
        ),
        _client.dio.get(
          '/api/v1.0/clients/display-owners/names',
          queryParameters: {
            'reqList': jsonEncode({'page': 0, 'size': 500}),
          },
        ),
      ]);

      final regionResponse = responses[0].data;
      final operatorsResponse = responses[1].data;

      final cities = _extractNamedItems(regionResponse);
      final operators = _extractNamedItems(operatorsResponse);

      return ServiceDashboardFiltersData(
        brands: const [],
        advertisers: const [],
        operators: operators,
        cities: cities,
        formats: const [],
        operatorIds: _extractNamedIdMap(operatorsResponse),
        cityIds: _extractNamedIdMap(regionResponse),
      );
    } catch (_) {
      return const ServiceDashboardFiltersData(
        brands: [],
        advertisers: [],
        operators: [],
        cities: [],
        formats: [],
        operatorIds: {},
        cityIds: {},
      );
    }
  }

  static Map<String, int> _extractNamedIdMap(dynamic data) {
    final rawItems = switch (data) {
      List<dynamic> _ => data,
      {'content': List<dynamic> content} => content,
      {'data': List<dynamic> items} => items,
      _ => const <dynamic>[],
    };

    final result = <String, int>{};
    for (final item in rawItems.whereType<Map<String, dynamic>>()) {
      final name = item['name']?.toString();
      final id = (item['id'] as num?)?.toInt();
      if (name != null && name.isNotEmpty && id != null) {
        result[name] = id;
      }
    }
    return result;
  }

  static List<String> _extractNamedItems(dynamic data) {
    final rawItems = switch (data) {
      List<dynamic> _ => data,
      {'content': List<dynamic> content} => content,
      {'data': List<dynamic> items} => items,
      _ => const <dynamic>[],
    };

    return rawItems
        .whereType<Map<String, dynamic>>()
        .map((item) => item['name']?.toString() ?? '')
        .where((name) => name.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
  }

  static ServiceDashboardFiltersData _buildFilters(
    List<Campaign> campaigns, {
    ServiceDashboardFiltersData? extraFilters,
  }) {
    final brands = <String>{};
    final advertisers = <String>{};
    final operators = <String>{};
    final cities = <String>{};
    final formats = <String>{};

    for (final campaign in campaigns) {
      if (campaign.brandName != null && campaign.brandName!.isNotEmpty) {
        brands.add(campaign.brandName!);
      }
      if (campaign.customerName != null && campaign.customerName!.isNotEmpty) {
        advertisers.add(campaign.customerName!);
      }
      operators.addAll(
        campaign.displayOwners.where((value) => value.isNotEmpty),
      );
      if (campaign.city != null && campaign.city!.isNotEmpty) {
        cities.add(campaign.city!);
      }
      formats.addAll(campaign.formats.where((value) => value.isNotEmpty));
    }

    if (extraFilters != null) {
      operators.addAll(extraFilters.operators);
      cities.addAll(extraFilters.cities);
    }

    List<String> sorted(Set<String> values) => values.toList()..sort();

    return ServiceDashboardFiltersData(
      brands: sorted(brands),
      advertisers: sorted(advertisers),
      operators: sorted(operators),
      cities: sorted(cities),
      formats: sorted(formats),
      operatorIds: extraFilters?.operatorIds ?? const {},
      cityIds: extraFilters?.cityIds ?? const {},
    );
  }

  static String _formatSpaceDateTime(DateTime value) {
    String pad(int n) => n.toString().padLeft(2, '0');
    return '${value.year}-${pad(value.month)}-${pad(value.day)} '
        '${pad(value.hour)}:${pad(value.minute)}:${pad(value.second)}';
  }
}

final serviceDashboardProvider =
    StateNotifierProvider.autoDispose<
      ServiceDashboardController,
      ServiceDashboardState
    >((ref) => ServiceDashboardController(ref));
