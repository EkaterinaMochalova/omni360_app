import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Что именно отмечено звёздочкой.
///
/// Кампании хранятся по id (имена меняются), а агентства и рекламодатели — по
/// имени: id рекламодателя в списочном ответе есть не всегда, а у агентства его
/// нет вовсе, и именно имя пользователь видит на карточке.
enum FavoriteKind { campaign, advertiser, agency }

extension FavoriteKindKey on FavoriteKind {
  String get storageKey => switch (this) {
    FavoriteKind.campaign => 'campaigns',
    FavoriteKind.advertiser => 'advertisers',
    FavoriteKind.agency => 'agencies',
  };

  String get title => switch (this) {
    FavoriteKind.campaign => 'Кампании',
    FavoriteKind.advertiser => 'Рекламодатели',
    FavoriteKind.agency => 'Агентства',
  };
}

/// Сохранение избранного поверх уже используемого в проекте
/// flutter_secure_storage — без новой зависимости (см. [LocalOrderStore]).
class FavoritesStore {
  const FavoritesStore._();

  static const FavoritesStore instance = FavoritesStore._();

  static const _key = 'omni360-favorites';
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  Future<Map<FavoriteKind, Set<String>>> load() async {
    final empty = {for (final kind in FavoriteKind.values) kind: <String>{}};
    final raw = await _storage.read(key: _key);
    if (raw == null) return empty;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return empty;
      final result = <FavoriteKind, Set<String>>{};
      for (final kind in FavoriteKind.values) {
        final stored = decoded[kind.storageKey];
        final keys = <String>{};
        if (stored is List) {
          for (final item in stored) {
            final key = item.toString();
            if (key.isNotEmpty) keys.add(key);
          }
        }
        result[kind] = keys;
      }
      return result;
    } catch (_) {
      // Повреждённые данные — начинаем с пустого избранного, а не падаем.
      return empty;
    }
  }

  Future<void> save(Map<FavoriteKind, Set<String>> favorites) {
    return _storage.write(
      key: _key,
      value: jsonEncode({
        for (final entry in favorites.entries)
          entry.key.storageKey: entry.value.toList(),
      }),
    );
  }
}
