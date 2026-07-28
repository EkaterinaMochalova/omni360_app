class AnalyticsOption {
  final int? id;
  final String key;
  final String label;

  const AnalyticsOption({this.id, required this.key, required this.label});

  factory AnalyticsOption.fromJson(Map<String, dynamic> json) {
    return AnalyticsOption(
      id: (json['id'] as num?)?.toInt(),
      key: (json['id'] ?? json['name'] ?? '').toString(),
      label: json['name']?.toString() ?? '',
    );
  }
}

class CampaignAnalyticsFiltersData {
  final List<AnalyticsOption> cities;
  final List<AnalyticsOption> displayOwners;
  final List<AnalyticsOption> creatives;
  final List<AnalyticsOption> creativeContents;
  final List<String> sides;
  final List<String> formats;
  final Map<String, String> failureReasons;
  final Map<String, String> states;

  const CampaignAnalyticsFiltersData({
    required this.cities,
    required this.displayOwners,
    required this.creatives,
    required this.creativeContents,
    required this.sides,
    required this.formats,
    required this.failureReasons,
    required this.states,
  });

  factory CampaignAnalyticsFiltersData.fromJson(Map<String, dynamic> json) {
    List<AnalyticsOption> parseOptions(String key) => (json[key] as List? ?? [])
        .map((item) => AnalyticsOption.fromJson(item as Map<String, dynamic>))
        .toList();

    List<String> parseStrings(String key) =>
        (json[key] as List? ?? []).map((item) => item.toString()).toList();

    Map<String, String> parseMap(String key) => Map<String, String>.from(
      (json[key] as Map? ?? {}).map(
        (k, v) => MapEntry(k.toString(), v.toString()),
      ),
    );

    return CampaignAnalyticsFiltersData(
      cities: parseOptions('cities'),
      displayOwners: parseOptions('displayOwners'),
      creatives: parseOptions('creativeNames'),
      creativeContents: parseOptions('creativeContentNames'),
      sides: parseStrings('sides'),
      formats: parseStrings('formats'),
      failureReasons: parseMap('failureReasonType'),
      states: parseMap('impressionStates'),
    );
  }
}

class CampaignImpressionRecord {
  final String id;
  final String? reqId;
  final String state;
  final String? failureReasonType;
  final String? failureReasonCodeName;
  final String? failureReasonMessage;
  final String? city;
  final String? address;
  final String? inventoryName;
  final String? inventoryGid;
  final String? side;
  final String? displayOwnerName;
  final String? mediaName;
  final DateTime? showTime;
  final double? bid;
  final double? bidFloor;
  final double? price;
  final double? chargedPrice;
  final double? cpm;

  const CampaignImpressionRecord({
    required this.id,
    required this.state,
    this.reqId,
    this.failureReasonType,
    this.failureReasonCodeName,
    this.failureReasonMessage,
    this.city,
    this.address,
    this.inventoryName,
    this.inventoryGid,
    this.side,
    this.displayOwnerName,
    this.mediaName,
    this.showTime,
    this.bid,
    this.bidFloor,
    this.price,
    this.chargedPrice,
    this.cpm,
  });

  factory CampaignImpressionRecord.fromJson(Map<String, dynamic> json) {
    final inventory = json['inventory'] as Map<String, dynamic>?;
    final displayOwner = json['displayOwnerDTO'] as Map<String, dynamic>?;
    final media = json['media'] as Map<String, dynamic>?;

    return CampaignImpressionRecord(
      id: json['id']?.toString() ?? '',
      reqId: json['reqId']?.toString(),
      state:
          json['bidRequestState']?.toString() ??
          json['state']?.toString() ??
          'UNKNOWN',
      failureReasonType: json['failureReasonType']?.toString(),
      failureReasonCodeName: json['failureReasonCodeName']?.toString(),
      failureReasonMessage: json['failureReasonMessage']?.toString(),
      city: json['city']?.toString(),
      address: json['address']?.toString(),
      inventoryName: inventory?['name']?.toString(),
      inventoryGid: json['inventoryGid']?.toString(),
      side: json['side']?.toString(),
      displayOwnerName: displayOwner?['name']?.toString(),
      mediaName: media?['name']?.toString(),
      showTime: _parseShowTime(json),
      bid: _toDouble(json['bid']),
      bidFloor: _toDouble(json['bidFloor']),
      price: _toDouble(json['price']),
      chargedPrice: _toDouble(json['chargedPrice']),
      cpm: _toDouble(json['cpm']),
    );
  }

  static double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  /// Момент показа.
  ///
  /// Читали только `showTime`/`inventoryShowTime`, и если бэкенд называет поле
  /// иначе, время оказывалось null у всех записей — а сводка по дням молча
  /// выбрасывает записи без времени и остаётся пустой. Поэтому перебираем
  /// известные имена, а не нашли — ищем любое поле, похожее на дату.
  static DateTime? _parseShowTime(Map<String, dynamic> json) {
    const knownKeys = [
      'showTime',
      'inventoryShowTime',
      'showDate',
      'impressionTime',
      'displayTime',
      'startTime',
      'requestTime',
      'bidTime',
      'createTime',
      'created',
      'timestamp',
    ];
    for (final key in knownKeys) {
      final parsed = _tryDate(json[key]);
      if (parsed != null) return parsed;
    }
    for (final entry in json.entries) {
      final name = entry.key.toLowerCase();
      if (!name.contains('time') && !name.contains('date')) continue;
      final parsed = _tryDate(entry.value);
      if (parsed != null) return parsed;
    }
    return null;
  }

  static DateTime? _tryDate(dynamic value) {
    if (value == null) return null;
    // Секунды/миллисекунды эпохи приходят числом, DateTime.tryParse их не берёт.
    if (value is num) {
      final asInt = value.toInt();
      if (asInt <= 0) return null;
      return DateTime.fromMillisecondsSinceEpoch(
        asInt < 100000000000 ? asInt * 1000 : asInt,
      );
    }
    final text = value.toString().trim();
    if (text.isEmpty) return null;
    // Формат "2026-07-27 14:05:00" ISO-разбор не принимает из-за пробела.
    return DateTime.tryParse(text.replaceFirst(' ', 'T'));
  }

  bool get isWin => state == 'WIN' || state == 'SUCCESS';
  bool get isLoss => state == 'FAILED';
}

/// Причина проигрыша показа с точки зрения того, что с ней делать дальше.
enum LossCategory {
  /// Проигрыш в аукционе из-за низкой ставки — нужно поднять ставку.
  lowBid,

  /// Показ не подтверждён SSP/плеером, причина неизвестна и т.п. —
  /// нужно разбираться с оператором.
  operatorIssue,
}

/// HEURISTIC: не проверено на реальных данных прод-API. Основной сигнал —
/// числовое сравнение bid/bidFloor (как в исходном Excel-отчёте, где причина
/// отказа текстом указывала "Ставка ниже чем минимальная ставка"). Если
/// бэкенд когда-нибудь начнёт отдавать явный код причины про низкую ставку,
/// он будет обработан первым без изменений в остальном коде.
/// TODO: сверить с реальными показами — всегда ли bid/bidFloor заполнены
/// у FAILED-записей, и встречается ли явный код причины "низкая ставка".
/// Числа в тексте причины отклонения — там указывается выигравшая ставка.
final _numberInText = RegExp(r'\d+(?:[.,]\d+)?');

/// Выигравшая ставка из причины отклонения, если она там названа.
///
/// Точная формулировка сообщения не зафиксирована в АПИ, поэтому берём
/// наибольшее число в тексте: ставка — единственная крупная величина в таких
/// сообщениях, а мелкие (номер попытки, код) её не перебьют. Если чисел нет
/// вовсе — возвращаем null, и рекомендация считается от минимальной ставки.
double? winningBidFromReason(CampaignImpressionRecord record) {
  final message = record.failureReasonMessage;
  if (message == null || message.trim().isEmpty) return null;

  double? best;
  for (final match in _numberInText.allMatches(message)) {
    final value = double.tryParse(match.group(0)!.replaceAll(',', '.'));
    if (value == null) continue;
    if (best == null || value > best) best = value;
  }
  return best;
}

LossCategory classifyLoss(CampaignImpressionRecord record) {
  final code = record.failureReasonCodeName?.toUpperCase() ?? '';
  final type = record.failureReasonType?.toUpperCase() ?? '';
  if (code.contains('BID') || type.contains('BID') || type.contains('FLOOR')) {
    return LossCategory.lowBid;
  }
  if (record.bid != null &&
      record.bidFloor != null &&
      record.bid! < record.bidFloor!) {
    return LossCategory.lowBid;
  }
  return LossCategory.operatorIssue;
}

class CampaignImpressionsPage {
  final List<CampaignImpressionRecord> content;
  final int page;
  final int totalPages;
  final int totalElements;
  final bool last;

  const CampaignImpressionsPage({
    required this.content,
    required this.page,
    required this.totalPages,
    required this.totalElements,
    required this.last,
  });

  factory CampaignImpressionsPage.fromJson(Map<String, dynamic> json) {
    return CampaignImpressionsPage(
      content: (json['content'] as List? ?? [])
          .map(
            (item) =>
                CampaignImpressionRecord.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
      page: (json['number'] as num?)?.toInt() ?? 0,
      totalPages: (json['totalPages'] as num?)?.toInt() ?? 1,
      totalElements: (json['totalElements'] as num?)?.toInt() ?? 0,
      last: json['last'] as bool? ?? true,
    );
  }
}

class CampaignAnalyticsAggregate {
  final int totalRequests;
  final int wins;
  final int losses;
  final int successes;
  final Map<String, int> stateCounts;
  final Map<String, int> failureCounts;

  const CampaignAnalyticsAggregate({
    required this.totalRequests,
    required this.wins,
    required this.losses,
    required this.successes,
    required this.stateCounts,
    required this.failureCounts,
  });

  factory CampaignAnalyticsAggregate.fromRecords(
    List<CampaignImpressionRecord> records,
  ) {
    final stateCounts = <String, int>{};
    final failureCounts = <String, int>{};

    for (final record in records) {
      stateCounts.update(record.state, (value) => value + 1, ifAbsent: () => 1);
      if (record.failureReasonType != null && record.failureReasonType!.isNotEmpty) {
        failureCounts.update(
          record.failureReasonType!,
          (value) => value + 1,
          ifAbsent: () => 1,
        );
      }
    }

    return CampaignAnalyticsAggregate(
      totalRequests: records.length,
      wins: records.where((record) => record.isWin).length,
      losses: records.where((record) => record.isLoss).length,
      successes: records.where((record) => record.state == 'SUCCESS').length,
      stateCounts: stateCounts,
      failureCounts: failureCounts,
    );
  }

  factory CampaignAnalyticsAggregate.empty() => const CampaignAnalyticsAggregate(
    totalRequests: 0,
    wins: 0,
    losses: 0,
    successes: 0,
    stateCounts: {},
    failureCounts: {},
  );
}

class CampaignAnalyticsDashboardPrefs {
  final bool showSummary;
  final bool showStateBreakdown;
  final bool showFailureBreakdown;
  final bool showRequestTable;
  final bool showDailyBreakdown;
  final bool showBidReport;
  final bool showOperatorReport;

  const CampaignAnalyticsDashboardPrefs({
    required this.showSummary,
    required this.showStateBreakdown,
    required this.showFailureBreakdown,
    required this.showRequestTable,
    required this.showDailyBreakdown,
    required this.showBidReport,
    required this.showOperatorReport,
  });

  const CampaignAnalyticsDashboardPrefs.defaults()
    : showSummary = true,
      showStateBreakdown = true,
      showFailureBreakdown = true,
      showRequestTable = true,
      showDailyBreakdown = true,
      showBidReport = true,
      showOperatorReport = true;

  CampaignAnalyticsDashboardPrefs copyWith({
    bool? showSummary,
    bool? showStateBreakdown,
    bool? showFailureBreakdown,
    bool? showRequestTable,
    bool? showDailyBreakdown,
    bool? showBidReport,
    bool? showOperatorReport,
  }) {
    return CampaignAnalyticsDashboardPrefs(
      showSummary: showSummary ?? this.showSummary,
      showStateBreakdown: showStateBreakdown ?? this.showStateBreakdown,
      showFailureBreakdown: showFailureBreakdown ?? this.showFailureBreakdown,
      showRequestTable: showRequestTable ?? this.showRequestTable,
      showDailyBreakdown: showDailyBreakdown ?? this.showDailyBreakdown,
      showBidReport: showBidReport ?? this.showBidReport,
      showOperatorReport: showOperatorReport ?? this.showOperatorReport,
    );
  }

  Map<String, dynamic> toJson() => {
    'showSummary': showSummary,
    'showStateBreakdown': showStateBreakdown,
    'showFailureBreakdown': showFailureBreakdown,
    'showRequestTable': showRequestTable,
    'showDailyBreakdown': showDailyBreakdown,
    'showBidReport': showBidReport,
    'showOperatorReport': showOperatorReport,
  };

  factory CampaignAnalyticsDashboardPrefs.fromJson(Map<String, dynamic> json) {
    return CampaignAnalyticsDashboardPrefs(
      showSummary: json['showSummary'] as bool? ?? true,
      showStateBreakdown: json['showStateBreakdown'] as bool? ?? true,
      showFailureBreakdown: json['showFailureBreakdown'] as bool? ?? true,
      showRequestTable: json['showRequestTable'] as bool? ?? true,
      showDailyBreakdown: json['showDailyBreakdown'] as bool? ?? true,
      showBidReport: json['showBidReport'] as bool? ?? true,
      showOperatorReport: json['showOperatorReport'] as bool? ?? true,
    );
  }
}
