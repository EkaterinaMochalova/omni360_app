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
      showTime: DateTime.tryParse(
        json['showTime']?.toString() ??
            json['inventoryShowTime']?.toString() ??
            '',
      ),
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

  bool get isWin => state == 'WIN' || state == 'SUCCESS';
  bool get isLoss => state == 'FAILED';
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

class CampaignAnalyticsDashboardPrefs {
  final bool showSummary;
  final bool showStateBreakdown;
  final bool showFailureBreakdown;
  final bool showRequestTable;

  const CampaignAnalyticsDashboardPrefs({
    required this.showSummary,
    required this.showStateBreakdown,
    required this.showFailureBreakdown,
    required this.showRequestTable,
  });

  const CampaignAnalyticsDashboardPrefs.defaults()
    : showSummary = true,
      showStateBreakdown = true,
      showFailureBreakdown = true,
      showRequestTable = true;

  CampaignAnalyticsDashboardPrefs copyWith({
    bool? showSummary,
    bool? showStateBreakdown,
    bool? showFailureBreakdown,
    bool? showRequestTable,
  }) {
    return CampaignAnalyticsDashboardPrefs(
      showSummary: showSummary ?? this.showSummary,
      showStateBreakdown: showStateBreakdown ?? this.showStateBreakdown,
      showFailureBreakdown: showFailureBreakdown ?? this.showFailureBreakdown,
      showRequestTable: showRequestTable ?? this.showRequestTable,
    );
  }

  Map<String, dynamic> toJson() => {
    'showSummary': showSummary,
    'showStateBreakdown': showStateBreakdown,
    'showFailureBreakdown': showFailureBreakdown,
    'showRequestTable': showRequestTable,
  };

  factory CampaignAnalyticsDashboardPrefs.fromJson(Map<String, dynamic> json) {
    return CampaignAnalyticsDashboardPrefs(
      showSummary: json['showSummary'] as bool? ?? true,
      showStateBreakdown: json['showStateBreakdown'] as bool? ?? true,
      showFailureBreakdown: json['showFailureBreakdown'] as bool? ?? true,
      showRequestTable: json['showRequestTable'] as bool? ?? true,
    );
  }
}
