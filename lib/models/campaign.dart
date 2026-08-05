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
    dayOfWeek: Campaign._toInt(json['dayOfWeek']) ?? 1,
    relativeStartTime: Campaign._toInt(json['relativeStartTime']) ?? 0,
    relativeEndTime: Campaign._toInt(json['relativeEndTime']) ?? 86400,
  );

  /// Собирает слоты расписания из ответа по кампании на любой глубине.
  ///
  /// `timeSettings` на верхнем уровне приходит пустым, а фактическое
  /// расписание задано глубже — на уровне сегментов. Поэтому ищем рекурсивно,
  /// а не по фиксированному пути: где именно оно лежит, зависит от кампании.
  ///
  /// Слоты из разных сегментов объединяем: кампания вещает, когда активен
  /// любой из них. Пересечения и стыки склеиваются уже при расчёте часов.
  static List<TimeSlot> collectFrom(dynamic node) {
    final found = <TimeSlot>[];
    final seen = <String>{};

    void walk(dynamic current, int depth) {
      if (depth > 8) return;
      if (current is Map) {
        final raw = current['timeSettings'];
        if (raw is List) {
          for (final entry in raw) {
            if (entry is! Map) continue;
            final slot = TimeSlot.fromJson(entry.cast<String, dynamic>());
            if (slot.relativeEndTime <= slot.relativeStartTime) continue;
            final key = '${slot.dayOfWeek}:'
                '${slot.relativeStartTime}:${slot.relativeEndTime}';
            if (seen.add(key)) found.add(slot);
          }
        }
        for (final value in current.values) {
          walk(value, depth + 1);
        }
      } else if (current is List) {
        for (final value in current) {
          walk(value, depth + 1);
        }
      }
    }

    walk(node, 0);
    return found;
  }
}

/// Смысловая категория статуса кампании — от неё зависят подпись и цвет.
enum CampaignStatusKind {
  active,
  paused,
  fresh,
  offSchedule,
  exhausted,
  completed,
  unknown,
}

/// Рекламная поверхность из состава кампании: GID, оператор, адрес.
///
/// Ответ `impression-inventory-stats`, по которому считаются фотоотчёты, знает
/// про поверхность только `inventory.id` и внутреннее имя. GID и оператор есть
/// здесь, в детальном ответе по кампании, — он уже загружен и закеширован, так
/// что связать одно с другим можно без единого дополнительного запроса.
class CampaignInventoryRef {
  final int id;
  final String gid;
  final String name;
  final String operatorName;
  final String address;
  final String city;

  const CampaignInventoryRef({
    required this.id,
    required this.gid,
    required this.name,
    required this.operatorName,
    required this.address,
    required this.city,
  });

  /// Собирает состав кампании с любой глубины ответа.
  ///
  /// Поверхности лежат в `segments[].inventories[]`, но раскладка отличается от
  /// кампании к кампании (как это уже было с расписанием), поэтому ищем
  /// рекурсивно. Признак поверхности — пара `id` + непустой `gid`.
  ///
  /// Оператор и город на самой поверхности обычно не указаны: они заданы выше,
  /// на уровне сегмента, — поэтому ближайшее найденное значение передаётся
  /// вниз по обходу.
  static Map<int, CampaignInventoryRef> collectFrom(Map<String, dynamic> json) {
    final found = <int, CampaignInventoryRef>{};

    // Ветки, где поверхностей быть не может, но есть свои id и gid: заходить в
    // них — значит рисковать принять бренд или агентство за экран.
    const skipKeys = {
      'brand',
      'customer',
      'agency',
      'createdBy',
      'budgetConfig',
      'photoReportSettings',
      'strategy',
      'warnings',
      'timeSettings',
    };

    String textOf(dynamic value) {
      if (value is String) return value.trim();
      if (value is Map) return value['name']?.toString().trim() ?? '';
      return '';
    }

    String firstText(List<dynamic> values, String fallback) {
      for (final value in values) {
        final text = textOf(value);
        if (text.isNotEmpty) return text;
      }
      return fallback;
    }

    void walk(dynamic current, int depth, String owner, String city, bool root) {
      if (depth > 10) return;
      if (current is Map) {
        final nextOwner = firstText([
          current['displayOwner'],
          current['displayOwnerDTO'],
          current['owner'],
        ], owner);
        final nextCity = firstText([current['city']], city);

        final id = Campaign._toInt(current['id']);
        final gid = current['gid']?.toString().trim() ?? '';
        // Корневой узел — сама кампания, у неё тоже есть id и gid.
        if (!root && id != null && gid.isNotEmpty) {
          found.putIfAbsent(
            id,
            () => CampaignInventoryRef(
              id: id,
              gid: gid,
              name: current['name']?.toString() ?? '',
              operatorName: nextOwner,
              address: firstText([
                current['address'],
                (current['location'] as Map?)?['address'],
              ], ''),
              city: nextCity,
            ),
          );
        }

        for (final entry in current.entries) {
          if (skipKeys.contains(entry.key.toString())) continue;
          walk(entry.value, depth + 1, nextOwner, nextCity, false);
        }
      } else if (current is List) {
        for (final value in current) {
          walk(value, depth + 1, owner, city, false);
        }
      }
    }

    walk(json, 0, '', '', true);

    if (found.isEmpty && (json['segments'] as List? ?? const []).isNotEmpty) {
      // Диагностика: сегменты есть, а поверхностей с gid в них не нашлось —
      // печатаем, как выглядит сегмент, чтобы не угадывать раскладку.
      final segment = (json['segments'] as List).first;
      // ignore: avoid_print
      print(
        '[inventory ${json['id']}] поверхности с gid не найдены. '
        'Ключи сегмента: ${segment is Map ? segment.keys.toList() : segment}',
      );
    }

    return found;
  }
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

  /// Агентство кампании. Нужно для избранного (можно отметить агентство и
  /// видеть все его кампании), поэтому храним имя как есть — оно же и ключ.
  final String? agencyName;
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
  final Map<String, int> displayOwnerNameToId;
  final List<String> formats;
  final List<TimeSlot>? timeSettings;

  /// Состав кампании: `inventory.id` → GID, оператор, адрес. Пустая карта у
  /// списочного ответа — поверхности приходят только в детальном.
  final Map<int, CampaignInventoryRef> inventories;

  const Campaign({
    required this.id,
    required this.name,
    required this.status,
    this.advertiser,
    this.customerId,
    this.customerName,
    this.brandId,
    this.brandName,
    this.agencyName,
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
    this.displayOwnerNameToId = const {},
    this.formats = const [],
    this.timeSettings,
    this.inventories = const {},
  });

  factory Campaign.fromJson(Map<String, dynamic> json) {
    final customer = json['customer'] as Map?;
    final brand = json['brand'] as Map?;
    final displayOwners = _extractDisplayOwners(json);
    final displayOwnerNameToId = _extractDisplayOwnerNameToId(json);

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
      customerId: _toInt(customer?['id']),
      customerName: customer?['name']?.toString(),
      brandId: _toInt(brand?['id']),
      brandName: brand?['name']?.toString(),
      agencyName: _extractName(json['agency']) ?? _extractName(json['agencyName']),
      // В детальном ответе бюджет лежит не там, где в списочном: наверху
      // totalBudget может быть пустым, а сумма — внутри budgetConfig. Из-за
      // этого блок «Выполнение лимита» считал, что бюджета нет вовсе.
      budget: _firstNumber(json, const [
        'totalBudget',
        'budget',
        'budgetBuyer',
      ], nested: json['budgetConfig']),
      dailyBudget: _firstNumber(json, const [
        'dailyBudget',
        'budgetPerDay',
        'dailyBudgetBuyer',
      ], nested: json['budgetConfig']),
      spent: _toDouble(json['spent'] ?? json['spentBudget']),
      // maxImpressionsCount сюда не берём: это лимит показов, а не контактов,
      // и он подставлялся первым — из-за него план по OTS показывался даже у
      // кампаний, где лимит по OTS не задан вовсе, причём числом другого
      // порядка. Нет настоящего OTS — пусть будет null и прочерк в интерфейсе.
      // Только явно заданный лимит по OTS. Сумма по инвентарям сегментов
      // (была запасным вариантом, ещё и домноженная на 1000) — это расчётная
      // ёмкость инвентаря, а не план кампании: она и давала «странный план»
      // там, где лимит по OTS не выставлен вообще.
      ots: _toDouble(json['ots'] ?? json['totalOts']),
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
      displayOwnerNameToId: displayOwnerNameToId,
      formats: _extractFormats(json),
      timeSettings: TimeSlot.collectFrom(json),
      inventories: CampaignInventoryRef.collectFrom(json),
    );
  }

  /// Имя сущности, которая в разных ответах приходит то объектом `{name: ...}`,
  /// то просто строкой (агентство — как раз такой случай).
  static String? _extractName(dynamic value) {
    if (value is Map) {
      final name = value['name']?.toString().trim();
      return (name == null || name.isEmpty) ? null : name;
    }
    if (value is String) {
      final name = value.trim();
      return name.isEmpty ? null : name;
    }
    return null;
  }

  /// Первое положительное число из [keys] — сначала на верхнем уровне, потом
  /// внутри [nested] (например budgetConfig). Именно положительное: часть
  /// полей приходит нулями, а не отсутствует.
  static double? _firstNumber(
    Map<String, dynamic> json,
    List<String> keys, {
    dynamic nested,
  }) {
    for (final key in keys) {
      final value = _toDouble(json[key]);
      if (value != null && value > 0) return value;
    }
    if (nested is Map) {
      for (final key in keys) {
        final value = _toDouble(nested[key]);
        if (value != null && value > 0) return value;
      }
    }
    return null;
  }

  static (List<int>, List<String>) _extractDisplayOwners(
    Map<String, dynamic> json,
  ) {
    final ids = <int>{};
    final names = <String>{};

    void addFrom(dynamic value) {
      if (value is Map) {
        final id = _toInt(value['id']);
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
      final segmentDisplayOwnerId = _toInt(segmentMap?['displayOwnerId']);
      if (segmentDisplayOwnerId != null) {
        ids.add(segmentDisplayOwnerId);
      }
      addFrom(segmentMap?['displayOwner']);
      addFrom(segmentMap?['displayOwnerDTO']);
    }

    return (ids.toList()..sort(), names.toList()..sort());
  }

  static Map<String, int> _extractDisplayOwnerNameToId(
    Map<String, dynamic> json,
  ) {
    final result = <String, int>{};

    void addFrom(dynamic value) {
      if (value is! Map) return;
      final name = value['name']?.toString();
      final id = _toInt(value['id']);
      if (name != null && name.isNotEmpty && id != null) {
        result[name] = id;
      }
    }

    for (final owner in json['displayOwners'] as List? ?? const []) {
      addFrom(owner);
    }

    for (final segment in json['segments'] as List? ?? const []) {
      final segmentMap = segment as Map?;
      addFrom(segmentMap?['displayOwner']);
      addFrom(segmentMap?['displayOwnerDTO']);
    }

    return result;
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
      final id = value is Map ? _toInt(value['id']) : _toInt(value);
      if (id != null) {
        ids.add(id);
      }
    }

    final targetCityId = _toInt((json['targetCity'] as Map?)?['id']);
    if (targetCityId != null) {
      ids.add(targetCityId);
    }

    return ids.toList()..sort();
  }

  static List<int> _extractSegmentIds(Map<String, dynamic> json) {
    final ids = <int>{};

    for (final segment in json['segments'] as List? ?? const []) {
      final id = _toInt((segment as Map?)?['id']);
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

  static int? _toInt(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
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
    Map<String, int>? displayOwnerNameToId,
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
      agencyName: agencyName,
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
      displayOwnerNameToId: displayOwnerNameToId ?? this.displayOwnerNameToId,
      formats: formats,
      timeSettings: timeSettings,
      inventories: inventories,
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

  /// Смысловая категория статуса — одна для подписи и для цвета.
  ///
  /// Раньше цвет плашки выбирался отдельным switch'ем по сырому статусу, а
  /// подпись — по признакам ниже. Бэкенд присылает не только RUNNING (бывает
  /// STARTED, LIVE, «Активна»), и на таких кампаниях плашка горела серым
  /// «Активна»: подпись из одного места, цвет из другого.
  CampaignStatusKind get statusKind {
    final s = status.toUpperCase();
    if (s == 'NEW') return CampaignStatusKind.fresh;
    if (s == 'COMPLETED') return CampaignStatusKind.completed;
    if (s == 'BUDGET_EXHAUSTED' || s == 'STOPPED') {
      return CampaignStatusKind.exhausted;
    }
    if (isActive) return CampaignStatusKind.active;
    if (isPaused) return CampaignStatusKind.paused;
    if (isNotOnSchedule) return CampaignStatusKind.offSchedule;
    return CampaignStatusKind.unknown;
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
  /// true — факт по OTS взят не из измеренного otsCountShowed, а из
  /// смоделированного/оценочного значения (totalDmpOts / totalEstimatedOts).
  final bool factOtsIsEstimated;
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
    this.factOtsIsEstimated = false,
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
    final customer = json['customerStats'] as Map?;
    // otsCount может быть 0 для FLEX_GUARANTEED — берём из reservedBudgetStat
    final planOts = _n(json['otsCount']) > 0
        ? _n(json['otsCount'])
        : _n(reserved?['ots']);
    // totalBudgetShowed приходит пустым для части кампаний, тогда реальная
    // сумма лежит в customerStats.budgetShowed — та же цепочка, что уже
    // используется в сервисном дашборде (_fetchCampaignTotalSpent).
    final factBudget = _firstPositive([
      json['totalBudgetShowed'],
      customer?['budgetShowed'],
      json['dailyBudgetShowed'],
    ]);
    // Факт по OTS. Реально измеренный факт — только otsCountShowed.
    // totalDmpOts — OTS, смоделированный по данным DMP, totalEstimatedOts —
    // расчётная оценка. Оставляем их как запасной вариант (иначе для части
    // кампаний факта не будет вовсе), но помечаем: выдавать оценку за факт
    // и считать от неё план/факт — значит показывать правдоподобную неправду.
    final otsShowed = _n(json['otsCountShowed']);
    final dmpOts = _n(json['totalDmpOts']);
    final estimatedOts = _n(json['totalEstimatedOts']);
    final factOts = otsShowed > 0
        ? otsShowed
        : (dmpOts > 0 ? dmpOts : estimatedOts);
    final factOtsIsEstimated = otsShowed <= 0 && factOts > 0;

    return CampaignStats(
      planBudget: _n(json['budget']) > 0
          ? _n(json['budget'])
          : _n(reserved?['budget']),
      planDailyBudget: _n(json['dailyBudget']) > 0
          ? _n(json['dailyBudget'])
          : _n(reserved?['dailyBudget']),
      planOts: planOts,
      factBudget: factBudget,
      factDailyBudget: _n(json['dailyBudgetShowed']),
      factOts: factOts,
      factOtsIsEstimated: factOtsIsEstimated,
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

  /// Первое положительное значение из списка кандидатов. Именно положительное,
  /// а не первое не-null: бэкенд отдаёт часть полей нулями, а не пропускает их.
  static double _firstPositive(List<dynamic> candidates) {
    for (final candidate in candidates) {
      final value = _n(candidate);
      if (value > 0) return value;
    }
    return 0;
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
