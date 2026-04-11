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
      state = state.copyWith(
        campaigns: AsyncValue.data(campaigns),
        filters: _buildFilters(campaigns),
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

      final response = await _fetchCampaignStats(
        filteredCampaigns,
        state.query,
      );
      final summaries = (response.data as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(ServiceDashboardCampaignSummary.fromJson)
          .toList();

      state = state.copyWith(summaries: AsyncValue.data(summaries));
    } catch (e, st) {
      state = state.copyWith(summaries: AsyncValue.error(e, st));
    }
  }

  Future<Response<dynamic>> _fetchCampaignStats(
    List<Campaign> campaigns,
    ServiceDashboardQuery query,
  ) async {
    final reqList = <String, dynamic>{
      'campaignIds': campaigns
          .map((campaign) => int.tryParse(campaign.id))
          .whereType<int>()
          .toList(),
      'startDate': _formatSpaceDateTime(query.start.toUtc()),
      'endDate': _formatSpaceDateTime(query.end.toUtc()),
      'cities': const <int>[],
      'creatives': const <int>[],
      'creativeContents': const <int>[],
      'states': const <String>[],
      'groupMode': 'SUMMARY',
      'page': 0,
      'size': campaigns.length.clamp(1, 2000).toInt(),
      'priceMode': 'CUSTOMER_CHARGE_INCLUDED',
      'withPlatformFee': false,
    };

    return _client.dio.get(
      '/api/v1.0/clients/impressions/campaigns-stats',
      queryParameters: {'reqList': jsonEncode(reqList)},
      options: Options(listFormat: ListFormat.multi),
    );
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

  static ServiceDashboardFiltersData _buildFilters(List<Campaign> campaigns) {
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

    List<String> sorted(Set<String> values) => values.toList()..sort();

    return ServiceDashboardFiltersData(
      brands: sorted(brands),
      advertisers: sorted(advertisers),
      operators: sorted(operators),
      cities: sorted(cities),
      formats: sorted(formats),
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
