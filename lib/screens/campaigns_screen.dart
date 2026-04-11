import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../main.dart';
import '../models/campaign.dart';
import '../providers/auth_provider.dart';
import '../providers/campaigns_provider.dart';
import '../services/app_notifications_service.dart';
import '../utils/campaign_notifications.dart';
import '../utils/pace_alerts.dart';
import 'campaign_detail.dart';
import 'campaign_create.dart';

// ── Sort enum ─────────────────────────────────────────────────────────────────

enum CampaignSort {
  nameAsc,
  nameDesc,
  budgetDesc,
  budgetAsc,
  spentDesc,
  startDateDesc,
  startDateAsc,
}

extension CampaignSortLabel on CampaignSort {
  String get label => switch (this) {
    CampaignSort.nameAsc => 'Название А–Я',
    CampaignSort.nameDesc => 'Название Я–А',
    CampaignSort.budgetDesc => 'Бюджет ↓',
    CampaignSort.budgetAsc => 'Бюджет ↑',
    CampaignSort.spentDesc => 'Потрачено ↓',
    CampaignSort.startDateDesc => 'Дата начала ↓',
    CampaignSort.startDateAsc => 'Дата начала ↑',
  };
}

// ── Main screen ───────────────────────────────────────────────────────────────

class CampaignsScreen extends ConsumerStatefulWidget {
  const CampaignsScreen({super.key});

  @override
  ConsumerState<CampaignsScreen> createState() => _CampaignsScreenState();
}

class _CampaignsScreenState extends ConsumerState<CampaignsScreen> {
  String _filter = 'Все';
  CampaignSort _sort = CampaignSort.nameAsc;
  final _searchCtrl = TextEditingController();
  String _search = '';
  Timer? _notificationTimer;
  bool _notificationCheckInProgress = false;
  bool _notificationsEnabled = true;
  bool _notificationPreferenceLoaded = false;
  int _unreadNotifications = 0;
  final List<CampaignNotice> _notifications = [];
  final Map<String, String> _lastStatuses = {};
  final Set<String> _sentNoticeKeys = {};

  static const _notificationCheckInterval = Duration(minutes: 5);

  static const _filters = [
    'Все',
    'Активна',
    'На паузе',
    'Не в графике',
    'Новая',
    'Завершена',
    'Бюджет исчерпан',
    'Не активна',
  ];

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() => setState(() => _search = _searchCtrl.text));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeNotificationPreferences();
    });
  }

  @override
  void dispose() {
    _notificationTimer?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _initializeNotificationPreferences() async {
    final enabled = await AppNotificationsService.instance.isEnabled();
    if (!mounted) return;
    setState(() {
      _notificationsEnabled = enabled;
      _notificationPreferenceLoaded = true;
    });
    if (enabled) {
      await _startNotificationChecks();
    }
  }

  Future<void> _startNotificationChecks() async {
    _notificationTimer?.cancel();
    if (!_notificationsEnabled) return;
    await AppNotificationsService.instance.requestPermissions();
    await _checkCampaignNotifications(primeCompletedStatus: true);
    _notificationTimer = Timer.periodic(
      _notificationCheckInterval,
      (_) => _checkCampaignNotifications(),
    );
  }

  Future<void> _checkCampaignNotifications({
    bool primeCompletedStatus = false,
  }) async {
    if (!_notificationsEnabled || _notificationCheckInProgress || !mounted) {
      return;
    }
    _notificationCheckInProgress = true;

    try {
      final campaigns = await ref
          .read(campaignsProvider.notifier)
          .fetch(silent: true);
      if (campaigns == null || !mounted) return;

      final previousStatuses = Map<String, String>.from(_lastStatuses);
      _lastStatuses
        ..clear()
        ..addEntries(campaigns.map((c) => MapEntry(c.id, c.status)));

      if (!primeCompletedStatus) {
        for (final campaign in campaigns) {
          final previousStatus = previousStatuses[campaign.id];
          if (previousStatus == null) continue;
          if (!isCampaignCompletedStatus(previousStatus) &&
              isCampaignCompleted(campaign)) {
            _pushNotification(
              CampaignNotice(
                key: 'completed:${campaign.id}',
                campaignId: campaign.id,
                campaignName: campaign.name,
                type: CampaignNoticeType.completed,
                title: 'Кампания завершена',
                message: 'Кампания "${campaign.name}" завершена.',
                createdAt: DateTime.now(),
              ),
            );
          }
        }
      }

      final now = DateTime.now();
      final activeCampaigns = campaigns.where(
        (campaign) => wasCampaignActiveForLastHour(campaign, now),
      );
      for (final campaign in activeCampaigns) {
        final stats = await ref.refresh(
          campaignStatsProvider(campaign.id).future,
        );
        if (!mounted) return;
        if (stats.hourlyExitsFact > 0) continue;

        final hourBucket = DateTime(now.year, now.month, now.day, now.hour);
        _pushNotification(
          CampaignNotice(
            key:
                'no-impressions:${campaign.id}:${hourBucket.toIso8601String()}',
            campaignId: campaign.id,
            campaignName: campaign.name,
            type: CampaignNoticeType.noImpressionsLastHour,
            title: 'Нет показов последний час',
            message:
                'У кампании "${campaign.name}" не было показов за последний час в активное время.',
            createdAt: now,
          ),
        );
      }
    } finally {
      _notificationCheckInProgress = false;
    }
  }

  void _pushNotification(CampaignNotice notice) {
    if (!_notificationsEnabled ||
        _sentNoticeKeys.contains(notice.key) ||
        !mounted) {
      return;
    }
    _sentNoticeKeys.add(notice.key);

    setState(() {
      _notifications.insert(0, notice);
      _unreadNotifications++;
    });

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('${notice.title}: ${notice.campaignName}'),
          behavior: SnackBarBehavior.floating,
        ),
      );

    AppNotificationsService.instance.show(
      dedupeKey: notice.key,
      title: notice.title,
      body: notice.message,
    );
  }

  Future<void> _toggleNotifications(bool value) async {
    await AppNotificationsService.instance.setEnabled(value);
    if (!mounted) return;

    setState(() {
      _notificationsEnabled = value;
      if (!value) {
        _unreadNotifications = 0;
      }
    });

    if (value) {
      await _startNotificationChecks();
    } else {
      _notificationTimer?.cancel();
      _notificationCheckInProgress = false;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
    }
  }

  void _openNotifications() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: kBorder,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Text(
                    'Уведомления',
                    style: TextStyle(
                      color: kTextPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const Spacer(),
                  if (_notificationPreferenceLoaded)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Вкл',
                          style: TextStyle(color: kTextSecondary, fontSize: 12),
                        ),
                        Switch.adaptive(
                          value: _notificationsEnabled,
                          activeThumbColor: kAccent,
                          activeTrackColor: kAccent.withValues(alpha: 0.35),
                          onChanged: _toggleNotifications,
                        ),
                      ],
                    ),
                  if (_notifications.isNotEmpty)
                    TextButton(
                      onPressed: () {
                        setState(_notifications.clear);
                        Navigator.pop(context);
                      },
                      child: const Text('Очистить'),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (!_notificationsEnabled)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Уведомления по кампаниям выключены.',
                    style: TextStyle(color: kTextSecondary),
                  ),
                )
              else if (_notifications.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Новых уведомлений пока нет.',
                    style: TextStyle(color: kTextSecondary),
                  ),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _notifications.length,
                    separatorBuilder: (_, unusedIndex) =>
                        const Divider(height: 20),
                    itemBuilder: (_, index) {
                      final notice = _notifications[index];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          backgroundColor:
                              notice.type == CampaignNoticeType.completed
                              ? const Color(0xFFE8F5E9)
                              : const Color(0xFFFFF3E0),
                          foregroundColor:
                              notice.type == CampaignNoticeType.completed
                              ? const Color(0xFF2E7D32)
                              : const Color(0xFFE65100),
                          child: Icon(
                            notice.type == CampaignNoticeType.completed
                                ? Icons.check_rounded
                                : Icons.warning_amber_rounded,
                          ),
                        ),
                        title: Text(notice.title),
                        subtitle: Text(
                          '${notice.message}\n${DateFormat('dd.MM.yyyy HH:mm').format(notice.createdAt)}',
                        ),
                        isThreeLine: true,
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    ).whenComplete(() {
      if (!mounted) return;
      setState(() => _unreadNotifications = 0);
    });
  }

  List<Campaign> _apply(List<Campaign> all) {
    var list = all;

    // Filter by status
    if (_filter != 'Все') {
      list = list.where((c) {
        final ds = c.displayStatus;
        return ds == _filter ||
            // catch variants
            (_filter == 'Не активна' &&
                !c.isActive &&
                !c.isPaused &&
                !c.isNotOnSchedule &&
                ds != 'Новая' &&
                ds != 'Завершена' &&
                ds != 'Бюджет исчерпан');
      }).toList();
    }

    // Search
    if (_search.isNotEmpty) {
      final q = _search.toLowerCase();
      list = list
          .where(
            (c) =>
                c.name.toLowerCase().contains(q) ||
                (c.advertiser?.toLowerCase().contains(q) ?? false),
          )
          .toList();
    }

    // Sort
    list = List.of(list);
    list.sort(
      (a, b) => switch (_sort) {
        CampaignSort.nameAsc => a.name.compareTo(b.name),
        CampaignSort.nameDesc => b.name.compareTo(a.name),
        CampaignSort.budgetDesc => (b.budget ?? 0).compareTo(a.budget ?? 0),
        CampaignSort.budgetAsc => (a.budget ?? 0).compareTo(b.budget ?? 0),
        CampaignSort.spentDesc => (b.spent ?? 0).compareTo(a.spent ?? 0),
        CampaignSort.startDateDesc => (b.startDate ?? '').compareTo(
          a.startDate ?? '',
        ),
        CampaignSort.startDateAsc => (a.startDate ?? '').compareTo(
          b.startDate ?? '',
        ),
      },
    );

    return list;
  }

  @override
  Widget build(BuildContext context) {
    final campaigns = ref.watch(campaignsProvider);

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Кампании',
          style: TextStyle(
            color: kTextPrimary,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        titleSpacing: 16,
        actions: [
          _HeaderActionButton(
            tooltip: _notificationsEnabled
                ? 'Уведомления'
                : 'Уведомления выключены',
            onTap: _openNotifications,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  _notificationsEnabled
                      ? Icons.notifications_none_rounded
                      : Icons.notifications_off_outlined,
                  color: kTextSecondary,
                  size: 21,
                ),
                if (_notificationsEnabled && _unreadNotifications > 0)
                  Positioned(
                    right: -6,
                    top: -7,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.redAccent,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 16,
                        minHeight: 16,
                      ),
                      child: Text(
                        _unreadNotifications > 9
                            ? '9+'
                            : '$_unreadNotifications',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // Sort button
          campaigns.maybeWhen(
            data: (_) => _HeaderActionButton(
              tooltip: 'Сортировка',
              onTap: () => _showSortSheet(context),
              child: const Icon(
                Icons.sort_rounded,
                color: kTextSecondary,
                size: 20,
              ),
            ),
            orElse: () => const SizedBox.shrink(),
          ),
          _HeaderActionButton(
            tooltip: 'Создать кампанию',
            onTap: () async {
              final created = await Navigator.of(context).push<bool>(
                MaterialPageRoute(builder: (_) => const CampaignCreateScreen()),
              );
              if (created == true && context.mounted) {
                ref.read(campaignsProvider.notifier).fetch();
              }
            },
            child: const Icon(Icons.add_rounded, color: kAccent, size: 21),
          ),
          _HeaderActionButton(
            tooltip: 'Обновить',
            onTap: () => ref.read(campaignsProvider.notifier).fetch(),
            child: const Icon(
              Icons.refresh_rounded,
              color: kTextSecondary,
              size: 20,
            ),
          ),
          _HeaderActionButton(
            tooltip: 'Выйти',
            onTap: () => ref.read(authProvider.notifier).logout(),
            child: const Icon(
              Icons.logout_rounded,
              color: kTextSecondary,
              size: 20,
            ),
          ),
          const SizedBox(width: 8),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(104),
          child: Column(
            children: [
              // Search bar
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: TextField(
                  controller: _searchCtrl,
                  style: const TextStyle(fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Поиск по названию или рекламодателю',
                    hintStyle: const TextStyle(
                      color: kTextSecondary,
                      fontSize: 14,
                    ),
                    prefixIcon: const Icon(
                      Icons.search,
                      color: kTextSecondary,
                      size: 20,
                    ),
                    suffixIcon: _search.isNotEmpty
                        ? IconButton(
                            icon: const Icon(
                              Icons.clear,
                              color: kTextSecondary,
                              size: 18,
                            ),
                            onPressed: () => _searchCtrl.clear(),
                          )
                        : null,
                    filled: true,
                    fillColor: kBg,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: kBorder),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: kAccent, width: 1.5),
                    ),
                  ),
                ),
              ),
              // Filter chips
              _FilterBar(
                selected: _filter,
                filters: _filters,
                onSelect: (f) => setState(() => _filter = f),
              ),
            ],
          ),
        ),
      ),
      body: campaigns.when(
        loading: () =>
            const Center(child: CircularProgressIndicator(color: kAccent)),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline,
                color: Colors.redAccent,
                size: 40,
              ),
              const SizedBox(height: 12),
              Text(
                e.toString(),
                style: const TextStyle(color: kTextSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => ref.read(campaignsProvider.notifier).fetch(),
                style: FilledButton.styleFrom(backgroundColor: kAccent),
                child: const Text('Повторить'),
              ),
            ],
          ),
        ),
        data: (all) {
          final list = _apply(all);
          return Column(
            children: [
              // Stats bar
              _StatsBar(all: all, filtered: list, sort: _sort),
              // List
              Expanded(
                child: list.isEmpty
                    ? const Center(
                        child: Text(
                          'Нет кампаний',
                          style: TextStyle(color: kTextSecondary, fontSize: 15),
                        ),
                      )
                    : RefreshIndicator(
                        color: kAccent,
                        onRefresh: () =>
                            ref.read(campaignsProvider.notifier).fetch(),
                        child: ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: list.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(height: 10),
                          itemBuilder: (_, i) => _CampaignCard(
                            campaign: list[i],
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => CampaignDetailScreen(
                                  campaignId: list[i].id,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showSortSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: kBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Сортировка',
              style: TextStyle(
                color: kTextPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 12),
            ...CampaignSort.values.map(
              (s) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  _sort == s
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  color: _sort == s ? kAccent : kTextSecondary,
                  size: 20,
                ),
                title: Text(
                  s.label,
                  style: TextStyle(
                    color: _sort == s ? kAccent : kTextPrimary,
                    fontSize: 14,
                    fontWeight: _sort == s
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
                ),
                onTap: () {
                  setState(() => _sort = s);
                  Navigator.pop(context);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Stats bar ─────────────────────────────────────────────────────────────────

class _StatsBar extends StatelessWidget {
  final List<Campaign> all;
  final List<Campaign> filtered;
  final CampaignSort sort;

  const _StatsBar({
    required this.all,
    required this.filtered,
    required this.sort,
  });

  @override
  Widget build(BuildContext context) {
    final active = filtered.where((c) => c.isActive).length;
    final fmt = NumberFormat.currency(
      locale: 'ru_RU',
      symbol: '₽',
      decimalDigits: 0,
    );
    // Бюджет только по отфильтрованным кампаниям
    final filteredBudget = filtered.fold<double>(
      0,
      (s, c) => s + (c.budget ?? 0),
    );
    final isFiltered = filtered.length != all.length;

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Row(
        children: [
          _StatChip(
            label: 'Всего',
            value: '${filtered.length}/${all.length}',
            color: kTextSecondary,
          ),
          const SizedBox(width: 12),
          _StatChip(
            label: 'Активных',
            value: '$active',
            color: const Color(0xFF2E7D32),
          ),
          const SizedBox(width: 12),
          _StatChip(
            label: isFiltered ? 'Бюджет (выбранных)' : 'Бюджет',
            value: fmt.format(filteredBudget),
            color: kAccent,
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StatChip({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(color: kTextSecondary, fontSize: 10)),
      Text(
        value,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
      ),
    ],
  );
}

// ── Filter chips ──────────────────────────────────────────────────────────────

class _FilterBar extends StatelessWidget {
  final String selected;
  final List<String> filters;
  final void Function(String) onSelect;

  const _FilterBar({
    required this.selected,
    required this.filters,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) => Container(
    color: Colors.white,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: Wrap(
      spacing: 8,
      runSpacing: 6,
      children: filters.map((f) {
        final sel = f == selected;
        return GestureDetector(
          onTap: () => onSelect(f),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: sel ? kAccent : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: sel ? kAccent : kBorder),
            ),
            child: Text(
              f,
              style: TextStyle(
                color: sel ? Colors.white : kTextSecondary,
                fontSize: 11,
                fontWeight: sel ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
        );
      }).toList(),
    ),
  );
}

// ── Campaign card ─────────────────────────────────────────────────────────────

class _CampaignCard extends ConsumerWidget {
  final Campaign campaign;
  final VoidCallback onTap;

  const _CampaignCard({required this.campaign, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fmt = NumberFormat.currency(
      locale: 'ru_RU',
      symbol: '₽',
      decimalDigits: 0,
    );
    final c = campaign;

    final (statusBg, statusFg) = _statusColors(c.status);
    final ratio = (c.spent != null && c.budget != null && c.budget! > 0)
        ? (c.spent! / c.budget!).clamp(0.0, 1.0)
        : null;

    // Алерты — загружаем stats только для активных кампаний
    final alertDots = c.isActive
        ? ref
              .watch(campaignStatsProvider(c.id))
              .whenOrNull(
                data: (stats) {
                  final alerts = buildAlerts(c, stats);
                  if (alerts.isEmpty) return null;
                  final hasOver = alerts.any((a) => a.type == PaceType.over);
                  final hasNoExits = alerts.any(
                    (a) => a.type == PaceType.noExits,
                  );
                  final hasUnder = alerts.any((a) => a.type == PaceType.under);
                  return (
                    hasOver: hasOver,
                    hasNoExits: hasNoExits,
                    hasUnder: hasUnder,
                  );
                },
              )
        : null;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Name + status
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    c.name,
                    style: const TextStyle(
                      color: kTextPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: statusBg,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    c.displayStatus,
                    style: TextStyle(
                      color: statusFg,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),

            if (alertDots != null) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                children: [
                  if (alertDots.hasOver)
                    _AlertDot(
                      '⚡ Перерасход',
                      const Color(0xFFC62828),
                      const Color(0xFFFFEBEE),
                    ),
                  if (alertDots.hasNoExits)
                    _AlertDot(
                      '⚠ Нет выходов/час',
                      const Color(0xFFE65100),
                      const Color(0xFFFFF3E0),
                    ),
                  if (alertDots.hasUnder)
                    _AlertDot(
                      '📉 Недотрата',
                      const Color(0xFF1565C0),
                      const Color(0xFFE3F2FD),
                    ),
                ],
              ),
            ],

            if (c.advertiser != null) ...[
              const SizedBox(height: 4),
              Text(
                c.advertiser!,
                style: const TextStyle(color: kTextSecondary, fontSize: 13),
              ),
            ],

            const SizedBox(height: 12),

            // Dates + budget
            Row(
              children: [
                if (c.startDate != null) ...[
                  const Icon(
                    Icons.calendar_today_outlined,
                    size: 13,
                    color: kTextSecondary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${c.startDate} – ${c.endDate ?? '...'}',
                    style: const TextStyle(color: kTextSecondary, fontSize: 12),
                  ),
                  const Spacer(),
                ],
                if (c.budget != null)
                  Text(
                    fmt.format(c.budget),
                    style: const TextStyle(
                      color: kTextPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
              ],
            ),

            // Budget progress bar
            if (ratio != null) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: ratio,
                  backgroundColor: const Color(0xFFE8EAF6),
                  valueColor: AlwaysStoppedAnimation(
                    ratio > 0.85 ? Colors.redAccent : kAccent,
                  ),
                  minHeight: 5,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Потрачено ${(ratio * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(color: kTextSecondary, fontSize: 11),
                  ),
                  Text(
                    fmt.format(c.spent),
                    style: const TextStyle(color: kTextSecondary, fontSize: 11),
                  ),
                ],
              ),
            ],

            // OTS / Выходы
            if (c.ots != null || c.exits != null) ...[
              const SizedBox(height: 12),
              const Divider(height: 1, color: kBorder),
              const SizedBox(height: 10),
              Row(
                children: [
                  if (c.ots != null)
                    _Metric(
                      'OTS',
                      NumberFormat.compact(locale: 'ru').format(c.ots),
                    ),
                  if (c.ots != null && c.exits != null)
                    const SizedBox(width: 24),
                  if (c.exits != null)
                    _Metric(
                      'Выходы',
                      NumberFormat.compact(locale: 'ru').format(c.exits),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  static (Color, Color) _statusColors(String status) {
    return switch (status.toUpperCase()) {
      'RUNNING' ||
      'ACTIVE' => (const Color(0xFFE8F5E9), const Color(0xFF2E7D32)),
      'PAUSED' => (const Color(0xFFFFF3E0), const Color(0xFFE65100)),
      'NEW' => (const Color(0xFFE3F2FD), const Color(0xFF1565C0)),
      'OFF_SCHEDULE' => (const Color(0xFFFFFDE7), const Color(0xFFF9A825)),
      'COMPLETED' => (const Color(0xFFF5F5F5), const Color(0xFF757575)),
      'BUDGET_EXHAUSTED' ||
      'STOPPED' => (const Color(0xFFFFEBEE), const Color(0xFFC62828)),
      _ => (const Color(0xFFF5F5F5), const Color(0xFF757575)),
    };
  }
}

class _AlertDot extends StatelessWidget {
  final String label;
  final Color color;
  final Color bg;
  const _AlertDot(this.label, this.color, this.bg);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(
      label,
      style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w500),
    ),
  );
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;
  const _Metric(this.label, this.value);

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(color: kTextSecondary, fontSize: 11)),
      const SizedBox(height: 2),
      Text(
        value,
        style: const TextStyle(
          color: kTextPrimary,
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
      ),
    ],
  );
}

class _HeaderActionButton extends StatelessWidget {
  final String tooltip;
  final VoidCallback onTap;
  final Widget child;

  const _HeaderActionButton({
    required this.tooltip,
    required this.onTap,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Padding(
        padding: const EdgeInsets.only(right: 4),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: SizedBox(width: 36, height: 36, child: Center(child: child)),
          ),
        ),
      ),
    );
  }
}
