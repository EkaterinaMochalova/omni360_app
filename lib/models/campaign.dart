/// Временной слот расписания кампании.
/// [relativeStartTime] и [relativeEndTime] — секунды от полуночи.
/// [dayOfWeek] — 1=Пн … 7=Вс (ISO 8601, совпадает с DateTime.weekday).
class TimeSlot {
  final int dayOfWeek;
  final int relativeStartTime;
  final int relativeEndTime;

  const TimeSlot({
    required this.dayOfWeek,
    required this.relativeStartTime,
    required this.relativeEndTime,
  });

  int get startHour => relativeStartTime ~/ 3600;
  int get endHour => (relativeEndTime / 3600).ceil().clamp(0, 24);

  factory TimeSlot.fromJson(Map<String, dynamic> json) => TimeSlot(
    dayOfWeek: (json['dayOfWeek'] as num?)?.toInt() ?? 1,
    relativeStartTime: (json['relativeStartTime'] as num?)?.toInt() ?? 0,
    relativeEndTime: (json['relativeEndTime'] as num?)?.toInt() ?? 86400,
  );
}

class Campaign {
  final String id;
  final String name;
  final String status;
  final String? advertiser;
  final int? customerId;
  final String? customerName;
  final int? brandId;
  final String? brandName;
  final double? budget;
  final double? dailyBudget;
  final double? spent;
  final double? ots;
  final double? exits;
  final String? startDate;
  final String? endDate;
  final String? type;
  final String? city;
  final List<int> cityIds;
  final List<String> regionCodes;
  final List<int> segmentIds;
  final List<int> displayOwnerIds;
  final List<String> displayOwners;
  final List<String> formats;
  final List<TimeSlot>? timeSettings;

  const Campaign({
    required this.id,
    required this.name,
    required this.status,
    this.advertiser,
    this.customerId,
    this.customerName,
    this.brandId,
    this.brandName,
    this.budget,
    this.dailyBudget,
    this.spent,
    this.ots,
    this.exits,
    this.startDate,
    this.endDate,
    this.type,
    this.city,
    this.cityIds = const [],
    this.regionCodes = const [],
    this.segmentIds = const [],
    this.displayOwnerIds = const [],
    this.displayOwners = const [],
    this.formats = const [],
    this.timeSettings,
  });

  factory Campaign.fromJson(Map<String, dynamic> json) {
    final customer = json['customer'] as Map?;
    final brand = json['brand'] as Map?;
    final displayOwners = _extractDisplayOwners(json);

    return Campaign(
      id: (json['id'] ?? json['campaignId'] ?? '').toString(),
      name: json['name'] ?? json['title'] ?? 'Без названия',
      status:
          json['state']?.toString() ?? json['status']?.toString() ?? 'unknown',
      advertiser:
          customer?['name']?.toString() ??
          brand?['name']?.toString() ??
          json['advertiser']?.toString() ??
          json['advertiserName']?.toString() ??
          json['clientName']?.toString(),
      customerId: (customer?['id'] as num?)?.toInt(),
      customerName: customer?['name']?.toString(),
      brandId: (brand?['id'] as num?)?.toInt(),
      brandName: brand?['name']?.toString(),
      budget: _toDouble(json['totalBudget'] ?? json['budget']),
      dailyBudget: _toDouble(json['dailyBudget'] ?? json['budgetPerDay']),
      spent: _toDouble(json['spent'] ?? json['spentBudget']),
      ots:
          _toDouble(
            json['maxImpressionsCount'] ?? json['ots'] ?? json['totalOts'],
          ) ??
          _otsFromSegments(json['segments']),
      exits: _toDouble(json['exits'] ?? json['totalExits'] ?? json['plays']),
      startDate: _trimDate(json['startDate']?.toString()),
      endDate: _trimDate(json['endDate']?.toString()),
      type: json['type']?.toString(),
      city:
          json['city']?.toString() ??
          (json['targetCity'] as Map?)?['name']?.toString(),
      cityIds: _extractCityIds(json),
      regionCodes: _extractRegionCodes(json),
      segmentIds: _extractSegmentIds(json),
      displayOwnerIds: displayOwners.$1,
      displayOwners: displayOwners.$2,
      formats: _extractFormats(json),
      timeSettings: (json['timeSettings'] as List?)
          ?.map((e) => TimeSlot.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

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

  static (List<int>, List<String>) _extractDisplayOwners(
    Map<String, dynamic> json,
  ) {
    final ids = <int>{};
    final names = <String>{};

    void addFrom(dynamic value) {
      if (value is Map) {
        final id = (value['id'] as num?)?.toInt();
        final name = value['name']?.toString();
        if (id != null) ids.add(id);
        if (name != null && name.isNotEmpty) names.add(name);
      }
    }

    for (final owner in json['displayOwners'] as List? ?? const []) {
      addFrom(owner);
    }

    for (final segment in json['segments'] as List? ?? const []) {
      final segmentMap = segment as Map?;
      final segmentDisplayOwnerId = (segmentMap?['displayOwnerId'] as num?)
          ?.toInt();
      if (segmentDisplayOwnerId != null) {
        ids.add(segmentDisplayOwnerId);
      }
      addFrom(segmentMap?['displayOwner']);
      addFrom(segmentMap?['displayOwnerDTO']);
    }

    return (ids.toList()..sort(), names.toList()..sort());
  }

  static List<String> _extractFormats(Map<String, dynamic> json) {
    final formats = <String>{};

    void add(dynamic value) {
      final stringValue = value?.toString();
      if (stringValue != null && stringValue.isNotEmpty) {
        formats.add(stringValue);
      }
    }

    add(json['format']);
    for (final value in json['formats'] as List? ?? const []) {
      add(value);
    }
    for (final segment in json['segments'] as List? ?? const []) {
      final segmentMap = segment as Map?;
      add(segmentMap?['format']);
      for (final inventory in segmentMap?['inventories'] as List? ?? const []) {
        final inventoryMap = inventory as Map?;
        add(inventoryMap?['format']);
        add(inventoryMap?['inventoryFormat']);
      }
    }

    return formats.toList()..sort();
  }

  static List<int> _extractCityIds(Map<String, dynamic> json) {
    final ids = <int>{};

    for (final value in json['cities'] as List? ?? const []) {
      final id = (value as num?)?.toInt();
      if (id != null) {
        ids.add(id);
      }
    }

    final targetCityId = ((json['targetCity'] as Map?)?['id'] as num?)?.toInt();
    if (targetCityId != null) {
      ids.add(targetCityId);
    }

    return ids.toList()..sort();
  }

  static List<int> _extractSegmentIds(Map<String, dynamic> json) {
    final ids = <int>{};

    for (final segment in json['segments'] as List? ?? const []) {
      final id = ((segment as Map?)?['id'] as num?)?.toInt();
      if (id != null) {
        ids.add(id);
      }
    }

    return ids.toList()..sort();
  }

  static List<String> _extractRegionCodes(Map<String, dynamic> json) {
    final codes = <String>{};

    void add(dynamic value) {
      final stringValue = value?.toString().trim().toUpperCase();
      if (stringValue != null && stringValue.isNotEmpty) {
        codes.add(stringValue);
      }
    }

    for (final segment in json['segments'] as List? ?? const []) {
      final segmentMap = segment as Map?;
      for (final region in segmentMap?['regions'] as List? ?? const []) {
        add(region);
      }
    }

    return codes.toList()..sort();
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

  Campaign copyWith({
    double? budget,
    String? city,
    List<int>? cityIds,
    List<String>? regionCodes,
    List<int>? segmentIds,
    List<int>? displayOwnerIds,
    List<String>? displayOwners,
  }) {
    return Campaign(
      id: id,
      name: name,
      status: status,
      advertiser: advertiser,
      customerId: customerId,
      customerName: customerName,
      brandId: brandId,
      brandName: brandName,
      budget: budget ?? this.budget,
      dailyBudget: dailyBudget,
      spent: spent,
      ots: ots,
      exits: exits,
      startDate: startDate,
      endDate: endDate,
      type: type,
      city: city ?? this.city,
      cityIds: cityIds ?? this.cityIds,
      regionCodes: regionCodes ?? this.regionCodes,
      segmentIds: segmentIds ?? this.segmentIds,
      displayOwnerIds: displayOwnerIds ?? this.displayOwnerIds,
      displayOwners: displayOwners ?? this.displayOwners,
      formats: formats,
      timeSettings: timeSettings,
    );
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
  final double planBudget; // budget
  final double planDailyBudget; // dailyBudget
  final double planOts; // otsCount

  // ФАКТ
  final double factBudget; // totalBudgetShowed
  final double factDailyBudget; // dailyBudgetShowed
  final double factOts; // otsCountShowed
  final int factExits; // totalCountShowed (кол-во выходов)

  // Часовые показатели (для расчёта темпа)
  final double hourlyBudgetPlan; // hourlyBudget
  final double hourlyBudgetFact; // hourlyBudgetShowed
  final double hourlyOtsPlan; // hourlyOts
  final double hourlyOtsFact; // hourlyOtsShowed
  final int hourlyExitsFact; // hourlyCountShowed

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
      planBudget: _n(json['budget']) > 0
          ? _n(json['budget'])
          : _n(reserved?['budget']),
      planDailyBudget: _n(json['dailyBudget']) > 0
          ? _n(json['dailyBudget'])
          : _n(reserved?['dailyBudget']),
      planOts: planOts,
      factBudget: _n(json['totalBudgetShowed']),
      factDailyBudget: _n(json['dailyBudgetShowed']),
      factOts: factOts,
      factExits: _n(json['totalCountShowed']).toInt(),
      hourlyBudgetPlan: _n(json['hourlyBudget']),
      hourlyBudgetFact: _n(json['hourlyBudgetShowed']),
      hourlyOtsPlan: _n(json['hourlyOts']),
      hourlyOtsFact: _n(json['hourlyOtsShowed']),
      hourlyExitsFact: _n(json['hourlyCountShowed']).toInt(),
      cpm: _n(json['cpm']),
      daily: const [],
    );
  }

  factory CampaignStats.empty() => const CampaignStats(
    planBudget: 0,
    planDailyBudget: 0,
    planOts: 0,
    factBudget: 0,
    factDailyBudget: 0,
    factOts: 0,
    factExits: 0,
    hourlyBudgetPlan: 0,
    hourlyBudgetFact: 0,
    hourlyOtsPlan: 0,
    hourlyOtsFact: 0,
    hourlyExitsFact: 0,
    cpm: 0,
    daily: [],
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
