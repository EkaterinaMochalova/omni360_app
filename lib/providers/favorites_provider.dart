import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/campaign.dart';
import '../services/favorites_store.dart';

@immutable
class FavoritesState {
  final Set<String> campaignIds;
  final Set<String> advertisers;
  final Set<String> agencies;

  /// Пока избранное не прочитано из хранилища, пустой набор значит «ещё не
  /// знаем», а не «ничего не отмечено» — от этого зависит, какой фильтр
  /// открывать по умолчанию.
  final bool loaded;

  const FavoritesState({
    this.campaignIds = const {},
    this.advertisers = const {},
    this.agencies = const {},
    this.loaded = false,
  });

  Set<String> of(FavoriteKind kind) => switch (kind) {
    FavoriteKind.campaign => campaignIds,
    FavoriteKind.advertiser => advertisers,
    FavoriteKind.agency => agencies,
  };

  bool contains(FavoriteKind kind, String key) => of(kind).contains(key);

  int get total => campaignIds.length + advertisers.length + agencies.length;

  bool get isEmpty => total == 0;

  bool get isNotEmpty => total > 0;

  /// Кампания попадает в избранное как сама по себе, так и через отмеченного
  /// рекламодателя или агентство.
  bool matches(Campaign campaign) {
    if (campaignIds.contains(campaign.id)) return true;
    final advertiser = campaign.advertiser;
    if (advertiser != null && advertisers.contains(advertiser)) return true;
    final agency = campaign.agencyName;
    return agency != null && agencies.contains(agency);
  }

  FavoritesState copyWith({
    Set<String>? campaignIds,
    Set<String>? advertisers,
    Set<String>? agencies,
    bool? loaded,
  }) {
    return FavoritesState(
      campaignIds: campaignIds ?? this.campaignIds,
      advertisers: advertisers ?? this.advertisers,
      agencies: agencies ?? this.agencies,
      loaded: loaded ?? this.loaded,
    );
  }
}

class FavoritesNotifier extends StateNotifier<FavoritesState> {
  FavoritesNotifier() : super(const FavoritesState()) {
    ready = _load();
  }

  /// Завершается, когда избранное прочитано из хранилища. Нужно экрану списка:
  /// решение «открыть Избранное вместо Активных» принимается один раз, и
  /// принимать его до загрузки нельзя.
  late final Future<void> ready;

  Future<void> _load() async {
    final stored = await FavoritesStore.instance.load();
    state = FavoritesState(
      campaignIds: stored[FavoriteKind.campaign] ?? const {},
      advertisers: stored[FavoriteKind.advertiser] ?? const {},
      agencies: stored[FavoriteKind.agency] ?? const {},
      loaded: true,
    );
  }

  void toggle(FavoriteKind kind, String key) {
    if (key.isEmpty) return;
    final next = Set<String>.from(state.of(kind));
    if (!next.remove(key)) next.add(key);

    state = switch (kind) {
      FavoriteKind.campaign => state.copyWith(campaignIds: next),
      FavoriteKind.advertiser => state.copyWith(advertisers: next),
      FavoriteKind.agency => state.copyWith(agencies: next),
    };

    FavoritesStore.instance.save({
      for (final k in FavoriteKind.values) k: state.of(k),
    });
  }
}

final favoritesProvider =
    StateNotifierProvider<FavoritesNotifier, FavoritesState>(
      (ref) => FavoritesNotifier(),
    );
