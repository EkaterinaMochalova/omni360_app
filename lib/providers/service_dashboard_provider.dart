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
  final Map<String, Campaign> _campaignDetailCache = {};
  final Map<String, Map<int, Map<String, dynamic>>> _campaignSegmentCache = {};

  Future<void> _load() async {
    await _loadCampaigns();
    await refresh();
  }

  Future<void> _loadCampaigns() async {
    try {
      final campaigns =
          await _ref.read(campaignsProvider.notifier).fetch(silent: true) ??
          const <Campaign>[];
      for (final campaign in campaigns) {
        _campaignDetailCache[campaign.id] = campaign;
      }
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
    var campaigns = state.campaigns.asData?.value;
    if (campaigns == null) return;

    state = state.copyWith(summaries: const AsyncValue.loading());
    try {
      if (state.query.operators.isNotEmpty || state.query.cities.isNotEmpty) {
        campaigns = await _enrichCampaignsForFilterDetails(
          campaigns,
          state.query,
        );
      }

      final filteredCampaigns = filterCampaigns(
        campaigns,
        state.query,
        filters: state.filters,
      );
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

  Future<List<Campaign>> _enrichCampaignsForFilterDetails(
    List<Campaign> campaigns,
    ServiceDashboardQuery query,
  ) async {
    final baseQuery = query.copyWith(operators: const {}, cities: const {});
    final candidates = filterCampaigns(
      campaigns,
      baseQuery,
      filters: state.filters,
    );
    final missingDetails = candidates
        .where(
          (campaign) => _needsDetailEnrichmentForFilters(campaign, query),
        )
        .toList();

    if (missingDetails.isEmpty) {
      return campaigns;
    }

    final enrichedById = <String, Campaign>{};
    const batchSize = 8;

    for (var i = 0; i < missingDetails.length; i += batchSize) {
      final chunk = missingDetails.skip(i).take(batchSize).toList();
      final chunkResults = await Future.wait(
        chunk.map((campaign) => _fetchCampaignDetailSafe(campaign, query)),
      );

      for (final campaign in chunkResults.whereType<Campaign>()) {
        enrichedById[campaign.id] = campaign;
        _campaignDetailCache[campaign.id] = campaign;
      }
    }

    if (enrichedById.isEmpty) {
      return campaigns;
    }

    final merged = campaigns
        .map((campaign) => enrichedById[campaign.id] ?? campaign)
        .toList();
    state = state.copyWith(
      campaigns: AsyncValue.data(merged),
      filters: _buildFilters(merged, extraFilters: state.filters),
    );
    return merged;
  }

  bool _needsDetailEnrichmentForFilters(
    Campaign campaign,
    ServiceDashboardQuery query,
  ) {
    final needsOperatorDetails =
        query.operators.isNotEmpty &&
        campaign.displayOwners.isEmpty &&
        campaign.displayOwnerIds.isEmpty;
    final needsCityDetails =
        query.cities.isNotEmpty &&
        campaign.city == null &&
        campaign.regionCodes.isEmpty &&
        campaign.cityIds.isEmpty;

    return needsOperatorDetails || needsCityDetails;
  }

  Future<Campaign?> _fetchCampaignDetailSafe(
    Campaign campaign,
    ServiceDashboardQuery query,
  ) async {
    final cached = _campaignDetailCache[campaign.id];
    if (cached != null && _hasUsefulCampaignDetails(cached)) {
      return _applyFilterBudgetFromSegments(cached, query);
    }

    try {
      final response = await _client.dio.get(
        '/api/v1.0/clients/campaigns/${campaign.id}',
        queryParameters: {'withPlatformFee': false},
      );
      if (response.data is Map<String, dynamic>) {
        final detailedCampaign = Campaign.fromJson(
          response.data as Map<String, dynamic>,
        );
        final enrichedCampaign = await _enrichCampaignFromSegments(
          detailedCampaign,
        );
        _campaignDetailCache[campaign.id] = enrichedCampaign;
        return _applyFilterBudgetFromSegments(enrichedCampaign, query);
      }
    } catch (_) {
      return cached ?? campaign;
    }

    return cached ?? campaign;
  }

  bool _hasUsefulCampaignDetails(Campaign campaign) {
    return campaign.displayOwners.isNotEmpty ||
        campaign.displayOwnerIds.isNotEmpty ||
        campaign.city != null ||
        campaign.cityIds.isNotEmpty ||
        campaign.regionCodes.isNotEmpty;
  }

  Future<Campaign> _enrichCampaignFromSegments(Campaign campaign) async {
    if (campaign.segmentIds.isEmpty) {
      return campaign;
    }

    final enrichedCityIds = {...campaign.cityIds};
    final enrichedCities = <String>{
      if (campaign.city != null && campaign.city!.isNotEmpty) campaign.city!,
    };
    final enrichedRegions = {...campaign.regionCodes};
    final enrichedOperatorIds = {...campaign.displayOwnerIds};
    final enrichedOperators = {...campaign.displayOwners};
    final segmentCache = <int, Map<String, dynamic>>{};

    for (final segmentId in campaign.segmentIds) {
      try {
        final response = await _client.dio.get(
          '/api/v1.0/clients/campaigns/${campaign.id}/segments/$segmentId',
          queryParameters: {'withPlatformFee': false},
        );

        final data = response.data;
        if (data is! Map<String, dynamic>) continue;
        segmentCache[segmentId] = data;

        final displayOwnerId =
            (data['displayOwnerId'] as num?)?.toInt() ??
            ((data['displayOwner'] as Map?)?['id'] as num?)?.toInt();
        final displayOwnerName =
            (data['displayOwner'] as Map?)?['name']?.toString();
        if (displayOwnerId != null) {
          enrichedOperatorIds.add(displayOwnerId);
        }
        if (displayOwnerName != null && displayOwnerName.isNotEmpty) {
          enrichedOperators.add(displayOwnerName);
        }

        void addLocationFrom(dynamic item) {
          final mapItem = item as Map?;
          final city = mapItem?['city'] as Map?;
          final cityId = (city?['id'] as num?)?.toInt();
          final cityName = city?['name']?.toString();
          if (cityId != null) {
            enrichedCityIds.add(cityId);
          }
          if (cityName != null && cityName.isNotEmpty) {
            enrichedCities.add(cityName);
          }

          final region = mapItem?['region'] as Map?;
          final regionName = region?['name']?.toString();
          if (regionName != null && regionName.isNotEmpty) {
            enrichedRegions.add(regionName.toUpperCase());
          }
        }

        addLocationFrom(data);
        for (final inventory in data['inventories'] as List? ?? const []) {
          addLocationFrom(inventory);
        }
      } catch (_) {
        continue;
      }
    }

    if (segmentCache.isNotEmpty) {
      _campaignSegmentCache[campaign.id] = segmentCache;
    }

    return campaign.copyWith(
      city: enrichedCities.isEmpty ? campaign.city : enrichedCities.first,
      cityIds: enrichedCityIds.toList()..sort(),
      regionCodes: enrichedRegions.toList()..sort(),
      displayOwnerIds: enrichedOperatorIds.toList()..sort(),
      displayOwners: enrichedOperators.toList()..sort(),
    );
  }

  Campaign _applyFilterBudgetFromSegments(
    Campaign campaign,
    ServiceDashboardQuery query,
  ) {
    if (query.operators.isEmpty && query.cities.isEmpty) {
      return campaign;
    }

    final segmentCache = _campaignSegmentCache[campaign.id];
    if (segmentCache == null || segmentCache.isEmpty) {
      return campaign;
    }

    final selectedOperatorIds = query.operators
        .map((name) => state.filters.operatorIds[name])
        .whereType<int>()
        .toSet();
    final selectedCityIds = query.cities
        .map((name) => state.filters.cityIds[name])
        .whereType<int>()
        .toSet();

    double matchedBudget = 0;
    var hasMatchedSegment = false;

    for (final data in segmentCache.values) {
      final segmentOperatorId =
          (data['displayOwnerId'] as num?)?.toInt() ??
          ((data['displayOwner'] as Map?)?['id'] as num?)?.toInt();
      final segmentOperatorName =
          (data['displayOwner'] as Map?)?['name']?.toString();

      final matchesOperator =
          query.operators.isEmpty ||
          (segmentOperatorId != null &&
              selectedOperatorIds.contains(segmentOperatorId)) ||
          (segmentOperatorName != null &&
              query.operators.contains(segmentOperatorName));

      if (!matchesOperator) {
        continue;
      }

      final inventories = (data['inventories'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList();

      bool inventoryMatchesCity(Map<String, dynamic> inventory) {
        if (query.cities.isEmpty) return true;

        final city = inventory['city'] as Map?;
        final cityId = (city?['id'] as num?)?.toInt();
        final cityName = city?['name']?.toString();
        final region = inventory['region'] as Map?;
        final regionName = region?['name']?.toString();

        if (cityId != null && selectedCityIds.contains(cityId)) {
          return true;
        }
        if (cityName != null && query.cities.contains(cityName)) {
          return true;
        }
        if (regionName != null &&
            _regionCodesForCity(regionName).any(campaign.regionCodes.contains)) {
          return true;
        }
        return false;
      }

      final matchingInventories = inventories.where(inventoryMatchesCity).toList();
      final matchesCity = query.cities.isEmpty || matchingInventories.isNotEmpty;
      if (!matchesCity) {
        continue;
      }

      hasMatchedSegment = true;
      if (matchingInventories.isNotEmpty) {
        matchedBudget += matchingInventories.fold<double>(
          0,
          (sum, inventory) => sum + _toDouble(inventory['budget']),
        );
      } else {
        matchedBudget += _toDouble(data['budget']);
      }
    }

    if (!hasMatchedSegment) {
      return campaign;
    }

    return campaign.copyWith(budget: matchedBudget);
  }

  double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  Future<List<ServiceDashboardCampaignSummary>> _fetchCampaignStats(
    List<Campaign> campaigns,
    ServiceDashboardQuery query,
    ServiceDashboardFiltersData filters,
  ) async {
    const chunkSize = 50;
    final chunkFutures = <Future<List<ServiceDashboardCampaignSummary>>>[];

    for (var i = 0; i < campaigns.length; i += chunkSize) {
      final chunk = campaigns.skip(i).take(chunkSize).toList();
      chunkFutures.add(_fetchProcessingFactChunk(chunk, query, filters));
    }

    final chunkResults = await Future.wait(chunkFutures);
    return chunkResults.expand((items) => items).toList();
  }

  Future<List<ServiceDashboardCampaignSummary>> _fetchProcessingFactChunk(
    List<Campaign> campaigns,
    ServiceDashboardQuery query,
    ServiceDashboardFiltersData filters,
  ) async {
    final ids = campaigns.map((campaign) => int.tryParse(campaign.id)).whereType<int>().toList();
    if (ids.isEmpty) return const [];

    final request = <String, dynamic>{
      'campaignIds': ids,
      'startDate': _formatApiDateTime(query.start),
      'endDate': _formatApiDateTime(query.end),
      'priceMode': 'CUSTOMER_CHARGE_INCLUDED',
      'withOts': true,
      'page': 0,
      'size': campaigns.length,
    };

    final variants = <Map<String, dynamic>>[
      request,
      {'request': jsonEncode(request)},
    ];

    for (final variant in variants) {
      try {
        final response = await _client.dio.get(
          '/api/v1.0/clients/campaigns/processing-stats',
          queryParameters: variant,
          options: Options(listFormat: ListFormat.multi),
        );
        final data = response.data;
        if (data is Map<String, dynamic>) {
          final content =
              (data['content'] as List? ?? const [])
                  .whereType<Map<String, dynamic>>()
                  .toList();
          if (content.isNotEmpty) {
            final byId = <int, Map<String, dynamic>>{};
            for (final item in content) {
              final campaignMap = item['campaign'] as Map<String, dynamic>?;
              final id = (campaignMap?['id'] as num?)?.toInt();
              if (id != null) byId[id] = item;
            }
            return campaigns
                .map((campaign) {
                  final id = int.tryParse(campaign.id);
                  if (id == null) return ServiceDashboardCampaignSummary.fromCampaign(campaign);
                  final item = byId[id];
                  if (item == null) {
                    return ServiceDashboardCampaignSummary.fromCampaign(campaign);
                  }
                  return ServiceDashboardCampaignSummary.fromProcessingStats(
                    campaign,
                    item,
                  );
                })
                .toList();
          }
        }
      } on DioException catch (e) {
        // ignore: avoid_print
        print(
          '[service-dashboard processing-stats] status=${e.response?.statusCode} data=${e.response?.data}',
        );
      }
    }

    return _fetchImpressionFactChunk(campaigns, query, filters);
  }

  Future<List<ServiceDashboardCampaignSummary>> _fetchImpressionFactChunk(
    List<Campaign> campaigns,
    ServiceDashboardQuery query,
    ServiceDashboardFiltersData filters,
  ) async {
    final summaries = await Future.wait(
      campaigns.map(
        (campaign) => _fetchImpressionFactForCampaign(campaign, query, filters),
      ),
    );

    return summaries.whereType<ServiceDashboardCampaignSummary>().toList();
  }

  Future<ServiceDashboardCampaignSummary?> _fetchImpressionFactForCampaign(
    Campaign campaign,
    ServiceDashboardQuery query,
    ServiceDashboardFiltersData filters,
  ) async {
    final campaignId = int.tryParse(campaign.id);
    if (campaignId == null) return null;

    try {
      final response = await _client.dio.get(
        '/api/v1.0/clients/campaigns/$campaignId/impression-stats',
        queryParameters: {'reqList': '{}'},
        options: Options(listFormat: ListFormat.multi),
      );
      final data = response.data;
      if (data is Map<String, dynamic>) {
        final stats = CampaignStats.fromImpressionStats(data);
        if (stats.hasData || stats.planBudget > 0) {
          return ServiceDashboardCampaignSummary.fromCampaignStats(
            campaign,
            stats,
          );
        }
      }
      return ServiceDashboardCampaignSummary.fromCampaign(campaign);
    } on DioException catch (e) {
      // ignore: avoid_print
      print(
        '[service-dashboard impression-stats] campaign=$campaignId status=${e.response?.statusCode} data=${e.response?.data}',
      );
      return ServiceDashboardCampaignSummary.fromCampaign(campaign);
    }
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
    ServiceDashboardQuery query, {
    ServiceDashboardFiltersData? filters,
  }) {
    final search = query.campaignSearch.trim().toLowerCase();
    final selectedOperatorIds = query.operators
        .map((name) => filters?.operatorIds[name])
        .whereType<int>()
        .toSet();
    final selectedCityIds = query.cities
        .map((name) => filters?.cityIds[name])
        .whereType<int>()
        .toSet();

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
          campaign.displayOwners.any(query.operators.contains) ||
          campaign.displayOwnerIds.any(selectedOperatorIds.contains);
      final matchesCity = _matchesSelectedCities(
        campaign,
        query.cities,
        selectedCityIds,
      );
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

  static bool _matchesSelectedCities(
    Campaign campaign,
    Set<String> cities,
    Set<int> cityIds,
  ) {
    if (cities.isEmpty) return true;

    final normalizedCampaignCity = _normalizeCityName(campaign.city);
    final campaignRegionCodes = campaign.regionCodes.toSet();
    final campaignCityIds = campaign.cityIds.toSet();

    if (campaignCityIds.any(cityIds.contains)) {
      return true;
    }

    for (final city in cities) {
      final normalizedSelectedCity = _normalizeCityName(city);
      if (normalizedCampaignCity != null &&
          normalizedCampaignCity == normalizedSelectedCity) {
        return true;
      }

      final candidateCodes = _regionCodesForCity(city);
      if (candidateCodes.any(campaignRegionCodes.contains)) {
        return true;
      }
    }

    return false;
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

  static String? _normalizeCityName(String? value) {
    if (value == null) return null;
    final normalized = value.trim().toLowerCase();
    return normalized.isEmpty ? null : normalized;
  }

  static String _formatApiDateTime(DateTime value) {
    String pad(int n) => n.toString().padLeft(2, '0');
    return '${value.year}-${pad(value.month)}-${pad(value.day)} '
        '${pad(value.hour)}:${pad(value.minute)}:${pad(value.second)}';
  }

  static Set<String> _regionCodesForCity(String city) {
    final normalized = city.trim().toLowerCase();
    if (normalized.isEmpty) return const {};

    if (normalized.contains('санкт') ||
        normalized.contains('петербург') ||
        normalized.contains('спб')) {
      return const {'SPB'};
    }

    if (normalized.contains('моск') && normalized.contains('обл')) {
      return const {'MOS'};
    }

    if (normalized.contains('моск')) {
      return const {'MSC'};
    }

    if (normalized.contains('друг') || normalized.contains('проч')) {
      return const {'OTHER'};
    }

    return const {};
  }
}

final serviceDashboardProvider =
    StateNotifierProvider.autoDispose<
      ServiceDashboardController,
      ServiceDashboardState
    >((ref) => ServiceDashboardController(ref));
