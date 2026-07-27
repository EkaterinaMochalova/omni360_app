import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Сохранение/загрузка пользовательского порядка перетаскиваемых
/// карточек/блоков (см. [ReorderableFlexWrap]) — поверх уже используемого в
/// проекте flutter_secure_storage (та же обёртка, что и для
/// campaign_analytics_dashboard_prefs), без новой зависимости.
class LocalOrderStore {
  const LocalOrderStore._();

  static const LocalOrderStore instance = LocalOrderStore._();

  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  Future<List<String>?> loadOrder(String key) async {
    final raw = await _storage.read(key: key);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.map((e) => e.toString()).toList();
      }
    } catch (_) {
      // Игнорируем повреждённые данные — используем порядок по умолчанию.
    }
    return null;
  }

  Future<void> saveOrder(String key, List<String> ids) {
    return _storage.write(key: key, value: jsonEncode(ids));
  }

  /// Сливает сохранённый порядок с актуальным списком id: сначала — те, что
  /// уже были в сохранённом порядке (и всё ещё существуют), в том же
  /// относительном порядке, затем — новые id, которых в сохранённом порядке
  /// не было (добавляются в конец, в их естественном порядке).
  List<String> mergeOrder(List<String> currentIds, List<String>? savedOrder) {
    if (savedOrder == null || savedOrder.isEmpty) return currentIds;

    final currentSet = currentIds.toSet();
    final merged = <String>[
      for (final id in savedOrder)
        if (currentSet.contains(id)) id,
    ];
    final mergedSet = merged.toSet();
    merged.addAll(currentIds.where((id) => !mergedSet.contains(id)));
    return merged;
  }

  /// Хранение доли ширины (0..1) на блок — для непрерывного ресайза плашек
  /// (см. [ReorderableFlexWrap.widthFractionOf]).
  Future<Map<String, double>?> loadWidths(String key) async {
    final raw = await _storage.read(key: key);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return decoded.map(
          (k, v) => MapEntry(k.toString(), (v as num).toDouble()),
        );
      }
    } catch (_) {
      // Игнорируем повреждённые данные — используем ширину по умолчанию.
    }
    return null;
  }

  Future<void> saveWidths(String key, Map<String, double> widths) {
    return _storage.write(key: key, value: jsonEncode(widths));
  }
}
