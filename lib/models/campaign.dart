class Campaign {
  final String id;
  final String name;
  final String status;
  final String? advertiser;   // Рекламодатель
  final double? budget;
  final double? dailyBudget;  // Бюджет в день
  final double? spent;
  final double? ots;          // OTS
  final double? exits;        // Выходы
  final String? startDate;
  final String? endDate;
  final String? type;
  final String? city;

  const Campaign({
    required this.id,
    required this.name,
    required this.status,
    this.advertiser,
    this.budget,
    this.dailyBudget,
    this.spent,
    this.ots,
    this.exits,
    this.startDate,
    this.endDate,
    this.type,
    this.city,
  });

  factory Campaign.fromJson(Map<String, dynamic> json) => Campaign(
        id: (json['id'] ?? json['campaignId'] ?? '').toString(),
        name: json['name'] ?? json['title'] ?? 'Без названия',
        status: json['state']?.toString() ?? json['status']?.toString() ?? 'unknown',
        advertiser: (json['customer'] as Map?)?['name']?.toString() ??
            (json['brand'] as Map?)?['name']?.toString() ??
            json['advertiser']?.toString() ??
            json['advertiserName']?.toString() ??
            json['clientName']?.toString(),
        budget: _toDouble(json['totalBudget'] ?? json['budget']),
        dailyBudget: _toDouble(json['dailyBudget'] ?? json['budgetPerDay']),
        spent: _toDouble(json['spent'] ?? json['spentBudget']),
        ots: _toDouble(json['maxImpressionsCount'] ?? json['ots'] ?? json['totalOts'])
            ?? _otsFromSegments(json['segments']),
        exits: _toDouble(json['exits'] ?? json['totalExits'] ?? json['plays']),
        startDate: _trimDate(json['startDate']?.toString()),
        endDate: _trimDate(json['endDate']?.toString()),
        type: json['type']?.toString(),
        city: json['city']?.toString() ??
            (json['targetCity'] as Map?)?['name']?.toString(),
      );

  /// Сумма OTS по всем инвентарям во всех сегментах (единиц × 1000 контактов)
  static double? _otsFromSegments(dynamic segments) {
    if (segments is! List || segments.isEmpty) return null;
    double total = 0;
    for (final seg in segments) {
      final inventories = (seg as Map?)?['inventories'];
      if (inventories is! List) continue;
      for (final inv in inventories) {
        final ots = _toDouble((inv as Map?)?['ots']);
        if (ots != null) total += ots;
      }
    }
    return total > 0 ? total * 1000 : null; // ots в тысячах контактов
  }

  static String? _trimDate(String? raw) {
    if (raw == null) return null;
    return raw.contains('T') ? raw.split('T').first : raw;
  }

  static double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return double.tryParse(value.toString());
  }

  bool get isActive {
    final s = status.toLowerCase();
    return s == 'active' ||
        s == 'running' ||
        s == 'активна' ||
        s == 'активный' ||
        s == 'активное' ||
        s == 'started' ||
        s == 'live' ||
        s == 'enabled' ||
        s.contains('activ');
  }

  bool get isPaused {
    final s = status.toLowerCase();
    return s == 'paused' ||
        s == 'pause' ||
        s == 'на паузе' ||
        s == 'приостановлена' ||
        s.contains('pause');
  }

  bool get isNotOnSchedule {
    final s = status.toLowerCase();
    return s == 'не в графике' ||
        s == 'off_schedule' ||
        s == 'off schedule' ||
        s == 'outofschedule' ||
        s.contains('schedule') ||
        s.contains('график');
  }

  /// Человекочитаемый статус для UI
  String get displayStatus {
    switch (status.toUpperCase()) {
      case 'RUNNING':
        return 'Активна';
      case 'PAUSED':
        return 'На паузе';
      case 'NEW':
        return 'Новая';
      case 'COMPLETED':
        return 'Завершена';
      case 'BUDGET_EXHAUSTED':
        return 'Бюджет исчерпан';
      case 'OFF_SCHEDULE':
        return 'Не в графике';
      case 'STOPPED':
        return 'Остановлена';
      default:
        if (isActive) return 'Активна';
        if (isPaused) return 'На паузе';
        if (isNotOnSchedule) return 'Не в графике';
        return status;
    }
  }
}

/// Статистика кампании из GET /impression-stats
class CampaignStats {
  // ПЛАН
  final double planBudget;       // budget
  final double planDailyBudget;  // dailyBudget
  final double planOts;          // otsCount

  // ФАКТ
  final double factBudget;       // totalBudgetShowed
  final double factDailyBudget;  // dailyBudgetShowed
  final double factOts;          // otsCountShowed
  final int factExits;           // totalCountShowed (кол-во выходов)

  // Часовые показатели (для расчёта темпа)
  final double hourlyBudgetPlan;    // hourlyBudget
  final double hourlyBudgetFact;    // hourlyBudgetShowed
  final double hourlyOtsPlan;       // hourlyOts
  final double hourlyOtsFact;       // hourlyOtsShowed
  final int    hourlyExitsFact;     // hourlyCountShowed

  // Дополнительно
  final double cpm;
  final List<DailyStat> daily;

  const CampaignStats({
    required this.planBudget,
    required this.planDailyBudget,
    required this.planOts,
    required this.factBudget,
    required this.factDailyBudget,
    required this.factOts,
    required this.factExits,
    required this.hourlyBudgetPlan,
    required this.hourlyBudgetFact,
    required this.hourlyOtsPlan,
    required this.hourlyOtsFact,
    required this.hourlyExitsFact,
    required this.cpm,
    required this.daily,
  });

  factory CampaignStats.fromImpressionStats(Map<String, dynamic> json) {
    final reserved = json['reservedBudgetStat'] as Map?;
    // otsCount может быть 0 для FLEX_GUARANTEED — берём из reservedBudgetStat
    final planOts = _n(json['otsCount']) > 0
        ? _n(json['otsCount'])
        : _n(reserved?['ots']);
    // factOts: otsCountShowed или dailyOtsShowed * дней
    final factOts = _n(json['otsCountShowed']) > 0
        ? _n(json['otsCountShowed'])
        : _n(json['totalDmpOts']) > 0
            ? _n(json['totalDmpOts'])
            : _n(json['totalEstimatedOts']);

    return CampaignStats(
      planBudget:      _n(json['budget']) > 0 ? _n(json['budget']) : _n(reserved?['budget']),
      planDailyBudget: _n(json['dailyBudget']) > 0 ? _n(json['dailyBudget']) : _n(reserved?['dailyBudget']),
      planOts:         planOts,
      factBudget:      _n(json['totalBudgetShowed']),
      factDailyBudget: _n(json['dailyBudgetShowed']),
      factOts:         factOts,
      factExits:       _n(json['totalCountShowed']).toInt(),
      hourlyBudgetPlan: _n(json['hourlyBudget']),
      hourlyBudgetFact: _n(json['hourlyBudgetShowed']),
      hourlyOtsPlan:    _n(json['hourlyOts']),
      hourlyOtsFact:    _n(json['hourlyOtsShowed']),
      hourlyExitsFact:  _n(json['hourlyCountShowed']).toInt(),
      cpm:             _n(json['cpm']),
      daily: const [],
    );
  }

  factory CampaignStats.empty() => const CampaignStats(
        planBudget: 0, planDailyBudget: 0, planOts: 0,
        factBudget: 0, factDailyBudget: 0, factOts: 0,
        factExits: 0,
        hourlyBudgetPlan: 0, hourlyBudgetFact: 0,
        hourlyOtsPlan: 0, hourlyOtsFact: 0, hourlyExitsFact: 0,
        cpm: 0, daily: [],
      );

  static double _n(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  bool get hasData => factBudget > 0 || factOts > 0 || factExits > 0;
}

class DailyStat {
  final String date;
  final int impressions;
  final double spent;

  const DailyStat({
    required this.date,
    required this.impressions,
    required this.spent,
  });

  factory DailyStat.fromJson(Map<String, dynamic> json) => DailyStat(
        date: json['date']?.toString() ?? '',
        impressions: (json['impressions'] as num?)?.toInt() ?? 0,
        spent: (json['spent'] as num?)?.toDouble() ?? 0.0,
      );
}
