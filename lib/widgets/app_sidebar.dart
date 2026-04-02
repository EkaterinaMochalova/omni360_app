import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../main.dart';
import '../providers/auth_provider.dart';

enum SidebarItem { overview, campaigns, creatives, analytics, employees }

final sidebarProvider = StateProvider<SidebarItem>((ref) => SidebarItem.campaigns);

class AppSidebar extends ConsumerWidget {
  const AppSidebar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(sidebarProvider);

    return Container(
      width: 220,
      decoration: const BoxDecoration(
        color: kSidebar,
        border: Border(right: BorderSide(color: kBorder)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Logo
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: kAccent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Center(
                    child: Text(
                      'O',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 18),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  'OmniBuy',
                  style: TextStyle(
                      color: kTextPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 18),
                ),
              ],
            ),
          ),

          // Nav items
          _NavItem(
            icon: Icons.grid_view_rounded,
            label: 'Обзор',
            selected: selected == SidebarItem.overview,
            onTap: () => ref.read(sidebarProvider.notifier).state =
                SidebarItem.overview,
          ),
          _NavItem(
            icon: Icons.campaign_outlined,
            label: 'Кампании',
            selected: selected == SidebarItem.campaigns,
            onTap: () => ref.read(sidebarProvider.notifier).state =
                SidebarItem.campaigns,
          ),
          _NavItem(
            icon: Icons.image_outlined,
            label: 'Рекл. материалы',
            selected: selected == SidebarItem.creatives,
            onTap: () => ref.read(sidebarProvider.notifier).state =
                SidebarItem.creatives,
          ),
          _NavItem(
            icon: Icons.bar_chart_rounded,
            label: 'Аналитика',
            selected: selected == SidebarItem.analytics,
            onTap: () => ref.read(sidebarProvider.notifier).state =
                SidebarItem.analytics,
          ),
          _NavItem(
            icon: Icons.people_outline,
            label: 'Сотрудники',
            selected: selected == SidebarItem.employees,
            onTap: () => ref.read(sidebarProvider.notifier).state =
                SidebarItem.employees,
          ),

          const Spacer(),

          // Bottom: user + balance
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: kBorder)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'User@mail.ru',
                  style: TextStyle(
                      color: kTextPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                const Text(
                  '1 000 000 ₽',
                  style: TextStyle(color: kTextSecondary, fontSize: 12),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Пополнить'),
                    style: FilledButton.styleFrom(
                      backgroundColor: kAccent,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      textStyle: const TextStyle(fontSize: 13),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: () {},
                  ),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  icon: const Icon(Icons.logout, size: 15, color: kTextSecondary),
                  label: const Text('Выйти',
                      style: TextStyle(color: kTextSecondary, fontSize: 13)),
                  onPressed: () =>
                      ProviderScope.containerOf(context, listen: false)
                          .read(authProvider.notifier)
                          .logout(),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 30),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? kAccentLight : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(icon,
                size: 18,
                color: selected ? kAccent : kTextSecondary),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: selected ? kAccent : kTextSecondary,
                fontWeight:
                    selected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
