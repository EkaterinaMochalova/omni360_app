import 'campaign.dart';

class ServiceDashboardQuery {
  final DateTime start;
  final DateTime end;
  final String campaignSearch;
  final Set<String> brands;
  final Set<String> advertisers;
  final Set<String> operators;
  final Set<String> cities;
  final Set<String> formats;

  const ServiceDashboardQuery({
    required this.start,
    required this.end,
    required this.campaignSearch,
    required this.brands,
    required this.advertisers,
    required this.operators,
    required this.cities,
    required this.formats,
  });

  factory ServiceDashboardQuery.initial() {
    final now = DateTime.now();
    return ServiceDashboardQuery(
      start: now.subtract(const Duration(days: 7)),
      end: now,
      campaignSearch: '',
      brands: const {},
      advertisers: const {},
      operators: const {},
      cities: const {},
      formats: const {},
    );
  }

  ServiceDashboardQuery copyWith({
    DateTime? start,
    DateTime? end,
    String? campaignSearch,
    Set<String>? brands,
    Set<String>? advertisers,
    Set<String>? operators,
    Set<String>? cities,
    Set<String>? formats,
  }) {
    return ServiceDashboardQuery(
      start: start ?? this.start,
      end: end ?? this.end,
      campaignSearch: campaignSearch ?? this.campaignSearch,
      brands: brands ?? this.brands,
      advertisers: advertisers ?? this.advertisers,
      operators: operators ?? this.operators,
      cities: cities ?? this.cities,
      formats: formats ?? this.formats,
    );
  }
}

class ServiceDashboardCampaignSummary {
  final int campaignId;
  final String campaignName;
  final double budget;
  final double spent;
  final int impressions;
  final int ots;
  final double showPrice;
  final double cpm;

  const ServiceDashboardCampaignSummary({
    required this.campaignId,
    required this.campaignName,
    required this.budget,
    required this.spent,
    required this.impressions,
    required this.ots,
    required this.showPrice,
    required this.cpm,
  });

  factory ServiceDashboardCampaignSummary.fromJson(Map<String, dynamic> json) {
    final campaign = json['campaign'] as Map<String, dynamic>?;
    return ServiceDashboardCampaignSummary(
      campaignId: (campaign?['id'] as num?)?.toInt() ?? 0,
      campaignName: campaign?['name']?.toString() ?? 'Без названия',
      budget: _toDouble(json['budget']),
      spent: _toDouble(json['totalBudgetShowed']),
      impressions: (json['totalCountShowed'] as num?)?.toInt() ?? 0,
      ots:
          (json['otsCountShowed'] as num?)?.toInt() ??
          (json['totalDmpOts'] as num?)?.toInt() ??
          (json['totalEstimatedOts'] as num?)?.toInt() ??
          0,
      showPrice: _toDouble(json['showPrice']),
      cpm: _toDouble(json['cpm']),
    );
  }

  factory ServiceDashboardCampaignSummary.fromInventoryStats(
    Campaign campaign,
    List<Map<String, dynamic>> rows,
  ) {
    final spent = rows.fold<double>(
      0,
      (sum, row) =>
          sum +
          _toDouble(
            row['customerStats'] is Map<String, dynamic>
                ? (row['customerStats'] as Map<String, dynamic>)['budgetShowed']
                : row['totalShowedBudget'],
          ),
    );
    final impressions = rows.fold<int>(
      0,
      (sum, row) => sum + ((row['totalShowed'] as num?)?.toInt() ?? 0),
    );
    final ots = rows.fold<int>(
      0,
      (sum, row) =>
          sum +
          ((row['totalOts'] as num?)?.toInt() ??
              (row['totalEstimatedOts'] as num?)?.toInt() ??
              0),
    );
    final weightedSpendForCpm = rows.fold<double>(
      0,
      (sum, row) => sum + _toDouble(row['totalShowedBudget']),
    );
    final showPrice = impressions > 0 ? spent / impressions : 0.0;
    final cpm = impressions > 0 ? (weightedSpendForCpm / impressions) * 1000 : 0.0;

    return ServiceDashboardCampaignSummary(
      campaignId: int.tryParse(campaign.id) ?? 0,
      campaignName: campaign.name,
      budget: campaign.budget ?? 0,
      spent: spent,
      impressions: impressions,
      ots: ots,
      showPrice: showPrice,
      cpm: cpm,
    );
  }

  factory ServiceDashboardCampaignSummary.fromImpressions(
    Campaign campaign,
    List<Map<String, dynamic>> rows,
  ) {
    final spent = rows.fold<double>(
      0,
      (sum, row) =>
          sum +
          _toDouble(
            row['chargedPrice'] ?? row['price'] ?? row['chargedCpm'],
          ),
    );
    final impressions = rows.length;
    final ots = rows.fold<int>(
      0,
      (sum, row) =>
          sum +
          ((row['ots'] as num?)?.toInt() ??
              (row['dmpOts'] as num?)?.toInt() ??
              (row['opOts'] as num?)?.toInt() ??
              (row['estOts'] as num?)?.toInt() ??
              0),
    );
    final showPrice = impressions > 0 ? spent / impressions : 0.0;
    final cpm = impressions > 0 ? showPrice * 1000 : 0.0;

    return ServiceDashboardCampaignSummary(
      campaignId: int.tryParse(campaign.id) ?? 0,
      campaignName: campaign.name,
      budget: campaign.budget ?? 0,
      spent: spent,
      impressions: impressions,
      ots: ots,
      showPrice: showPrice,
      cpm: cpm,
    );
  }

  factory ServiceDashboardCampaignSummary.fromCampaignStats(
    Campaign campaign,
    CampaignStats stats,
  ) {
    final impressions = stats.factExits;
    final spent = stats.factBudget;
    final ots = stats.factOts.round();
    final showPrice = impressions > 0 ? spent / impressions : 0.0;
    final cpm = stats.cpm > 0 ? stats.cpm : (impressions > 0 ? showPrice * 1000 : 0.0);

    return ServiceDashboardCampaignSummary(
      campaignId: int.tryParse(campaign.id) ?? 0,
      campaignName: campaign.name,
      budget: campaign.budget ?? stats.planBudget,
      spent: spent,
      impressions: impressions,
      ots: ots,
      showPrice: showPrice,
      cpm: cpm,
    );
  }

  factory ServiceDashboardCampaignSummary.fromCampaign(Campaign campaign) {
    final budget = campaign.budget ?? 0;
    final spent = campaign.spent ?? 0;
    final impressions = (campaign.exits ?? 0).round();
    final ots = (campaign.ots ?? 0).round();
    final averageShowPrice = impressions > 0 ? spent / impressions : 0.0;
    final cpm = impressions > 0 ? (spent / impressions) * 1000 : 0.0;

    return ServiceDashboardCampaignSummary(
      campaignId: int.tryParse(campaign.id) ?? 0,
      campaignName: campaign.name,
      budget: budget,
      spent: spent,
      impressions: impressions,
      ots: ots,
      showPrice: averageShowPrice,
      cpm: cpm,
    );
  }

  static double _toDouble(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0;
  }
}

class ServiceDashboardTotals {
  final int campaignCount;
  final int activeCampaignCount;
  final double totalBudget;
  final double totalSpent;
  final int totalImpressions;
  final int totalOts;
  final double averageBid;
  final double averageCpm;

  const ServiceDashboardTotals({
    required this.campaignCount,
    required this.activeCampaignCount,
    required this.totalBudget,
    required this.totalSpent,
    required this.totalImpressions,
    required this.totalOts,
    required this.averageBid,
    required this.averageCpm,
  });
}

class ServiceDashboardFiltersData {
  final List<String> brands;
  final List<String> advertisers;
  final List<String> operators;
  final List<String> cities;
  final List<String> formats;
  final Map<String, int> operatorIds;
  final Map<String, int> cityIds;

  const ServiceDashboardFiltersData({
    required this.brands,
    required this.advertisers,
    required this.operators,
    required this.cities,
    required this.formats,
    this.operatorIds = const {},
    this.cityIds = const {},
  });
}
