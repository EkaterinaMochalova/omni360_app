import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../main.dart';
import '../providers/auth_provider.dart';
import '../providers/campaigns_provider.dart';
import '../models/campaign.dart';
import 'campaign_detail.dart';

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
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
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
          .where((c) =>
              c.name.toLowerCase().contains(q) ||
              (c.advertiser?.toLowerCase().contains(q) ?? false))
          .toList();
    }

    // Sort
    list = List.of(list);
    list.sort((a, b) => switch (_sort) {
          CampaignSort.nameAsc => a.name.compareTo(b.name),
          CampaignSort.nameDesc => b.name.compareTo(a.name),
          CampaignSort.budgetDesc =>
            (b.budget ?? 0).compareTo(a.budget ?? 0),
          CampaignSort.budgetAsc =>
            (a.budget ?? 0).compareTo(b.budget ?? 0),
          CampaignSort.spentDesc =>
            (b.spent ?? 0).compareTo(a.spent ?? 0),
          CampaignSort.startDateDesc =>
            (b.startDate ?? '').compareTo(a.startDate ?? ''),
          CampaignSort.startDateAsc =>
            (a.startDate ?? '').compareTo(b.startDate ?? ''),
        });

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
              fontSize: 20),
        ),
        actions: [
          // Sort button
          campaigns.maybeWhen(
            data: (_) => IconButton(
              icon: const Icon(Icons.sort_rounded, color: kTextSecondary),
              onPressed: () => _showSortSheet(context),
              tooltip: 'Сортировка',
            ),
            orElse: () => const SizedBox.shrink(),
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: kTextSecondary),
            onPressed: () => ref.read(campaignsProvider.notifier).fetch(),
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: kTextSecondary),
            onPressed: () => ref.read(authProvider.notifier).logout(),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(104),
          child: Column(
            children: [
              // Search bar
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: TextField(
                  controller: _searchCtrl,
                  style: const TextStyle(fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Поиск по названию или рекламодателю',
                    hintStyle:
                        const TextStyle(color: kTextSecondary, fontSize: 14),
                    prefixIcon:
                        const Icon(Icons.search, color: kTextSecondary, size: 20),
                    suffixIcon: _search.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear,
                                color: kTextSecondary, size: 18),
                            onPressed: () => _searchCtrl.clear(),
                          )
                        : null,
                    filled: true,
                    fillColor: kBg,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
              const Icon(Icons.error_outline, color: Colors.redAccent, size: 40),
              const SizedBox(height: 12),
              Text(e.toString(),
                  style: const TextStyle(color: kTextSecondary),
                  textAlign: TextAlign.center),
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
                        child: Text('Нет кампаний',
                            style: TextStyle(
                                color: kTextSecondary, fontSize: 15)),
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
                                    campaignId: list[i].id),
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
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
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
            const Text('Сортировка',
                style: TextStyle(
                    color: kTextPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 16)),
            const SizedBox(height: 12),
            ...CampaignSort.values.map((s) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    _sort == s
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    color: _sort == s ? kAccent : kTextSecondary,
                    size: 20,
                  ),
                  title: Text(s.label,
                      style: TextStyle(
                          color: _sort == s ? kAccent : kTextPrimary,
                          fontSize: 14,
                          fontWeight: _sort == s
                              ? FontWeight.w600
                              : FontWeight.normal)),
                  onTap: () {
                    setState(() => _sort = s);
                    Navigator.pop(context);
                  },
                )),
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

  const _StatsBar(
      {required this.all, required this.filtered, required this.sort});

  @override
  Widget build(BuildContext context) {
    final active = all.where((c) => c.isActive).length;
    final fmt = NumberFormat.currency(
        locale: 'ru_RU', symbol: '₽', decimalDigits: 0);
    final totalBudget = all.fold<double>(0, (s, c) => s + (c.budget ?? 0));

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Row(
        children: [
          _StatChip(
              label: 'Всего',
              value: '${filtered.length}/${all.length}',
              color: kTextSecondary),
          const SizedBox(width: 12),
          _StatChip(
              label: 'Активных',
              value: '$active',
              color: const Color(0xFF2E7D32)),
          const SizedBox(width: 12),
          _StatChip(
              label: 'Бюджет',
              value: fmt.format(totalBudget),
              color: kAccent),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StatChip(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style:
                  const TextStyle(color: kTextSecondary, fontSize: 10)),
          Text(value,
              style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w700,
                  fontSize: 13)),
        ],
      );
}

// ── Filter chips ──────────────────────────────────────────────────────────────

class _FilterBar extends StatelessWidget {
  final String selected;
  final List<String> filters;
  final void Function(String) onSelect;

  const _FilterBar(
      {required this.selected,
      required this.filters,
      required this.onSelect});

  @override
  Widget build(BuildContext context) => Container(
        color: Colors.white,
        height: 44,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          itemCount: filters.length,
          separatorBuilder: (context, index) => const SizedBox(width: 8),
          itemBuilder: (_, i) {
            final f = filters[i];
            final sel = f == selected;
            return GestureDetector(
              onTap: () => onSelect(f),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                decoration: BoxDecoration(
                  color: sel ? kAccent : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: sel ? kAccent : kBorder),
                ),
                child: Text(
                  f,
                  style: TextStyle(
                    color: sel ? Colors.white : kTextSecondary,
                    fontSize: 13,
                    fontWeight: sel ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
            );
          },
        ),
      );
}

// ── Campaign card ─────────────────────────────────────────────────────────────

class _CampaignCard extends StatelessWidget {
  final Campaign campaign;
  final VoidCallback onTap;

  const _CampaignCard({required this.campaign, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat.currency(
        locale: 'ru_RU', symbol: '₽', decimalDigits: 0);
    final c = campaign;

    final (statusBg, statusFg) = _statusColors(c.status);
    final ratio = (c.spent != null && c.budget != null && c.budget! > 0)
        ? (c.spent! / c.budget!).clamp(0.0, 1.0)
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
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusBg,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(c.displayStatus,
                      style: TextStyle(
                          color: statusFg,
                          fontSize: 12,
                          fontWeight: FontWeight.w500)),
                ),
              ],
            ),

            if (c.advertiser != null) ...[
              const SizedBox(height: 4),
              Text(c.advertiser!,
                  style: const TextStyle(
                      color: kTextSecondary, fontSize: 13)),
            ],

            const SizedBox(height: 12),

            // Dates + budget
            Row(
              children: [
                if (c.startDate != null) ...[
                  const Icon(Icons.calendar_today_outlined,
                      size: 13, color: kTextSecondary),
                  const SizedBox(width: 4),
                  Text(
                    '${c.startDate} – ${c.endDate ?? '...'}',
                    style: const TextStyle(
                        color: kTextSecondary, fontSize: 12),
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
                      ratio > 0.85 ? Colors.redAccent : kAccent),
                  minHeight: 5,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Потрачено ${(ratio * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(
                        color: kTextSecondary, fontSize: 11),
                  ),
                  Text(
                    fmt.format(c.spent),
                    style: const TextStyle(
                        color: kTextSecondary, fontSize: 11),
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
                    _Metric('OTS',
                        NumberFormat.compact(locale: 'ru').format(c.ots)),
                  if (c.ots != null && c.exits != null)
                    const SizedBox(width: 24),
                  if (c.exits != null)
                    _Metric('Выходы',
                        NumberFormat.compact(locale: 'ru').format(c.exits)),
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
      'RUNNING' || 'ACTIVE' => (
          const Color(0xFFE8F5E9),
          const Color(0xFF2E7D32)
        ),
      'PAUSED' => (const Color(0xFFFFF3E0), const Color(0xFFE65100)),
      'NEW' => (const Color(0xFFE3F2FD), const Color(0xFF1565C0)),
      'OFF_SCHEDULE' => (const Color(0xFFFFFDE7), const Color(0xFFF9A825)),
      'COMPLETED' => (const Color(0xFFF5F5F5), const Color(0xFF757575)),
      'BUDGET_EXHAUSTED' || 'STOPPED' => (
          const Color(0xFFFFEBEE),
          const Color(0xFFC62828)
        ),
      _ => (const Color(0xFFF5F5F5), const Color(0xFF757575)),
    };
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;
  const _Metric(this.label, this.value);

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  color: kTextSecondary, fontSize: 11)),
          const SizedBox(height: 2),
          Text(value,
              style: const TextStyle(
                color: kTextPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              )),
        ],
      );
}
