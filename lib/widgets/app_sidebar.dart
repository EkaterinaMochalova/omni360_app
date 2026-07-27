import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../main.dart';
import '../providers/auth_provider.dart';
import '../screens/budgets_pace_screen.dart';
import '../screens/service_dashboard_screen.dart';

/// Разделы, между которыми ходим из сайдбара.
enum AppSection { campaigns, serviceDashboard, budgetsPace }

/// Экран с постоянным сайдбаром слева. Оборачивает уже готовый Scaffold
/// раздела, чтобы не переписывать его вёрстку.
class AppShell extends StatelessWidget {
  final AppSection section;
  final Widget child;

  const AppShell({super.key, required this.section, required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: Row(
        children: [
          AppSidebar(current: section),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// Левая панель: лого, переходы между разделами, текущий логин и выход.
class AppSidebar extends ConsumerWidget {
  /// Раздел, на котором мы сейчас, — он подсвечивается и не перекладывает
  /// экран сам на себя.
  final AppSection current;

  const AppSidebar({super.key, required this.current});

  void _go(BuildContext context, AppSection target) {
    if (target == current) return;

    // Список кампаний — корень навигации, к нему возвращаемся, а не кладём
    // сверху ещё одну копию: иначе «назад» уводит в стопку одинаковых экранов.
    if (target == AppSection.campaigns) {
      Navigator.of(context).popUntil((route) => route.isFirst);
      return;
    }

    final route = MaterialPageRoute<void>(
      builder: (_) => switch (target) {
        AppSection.serviceDashboard => const ServiceDashboardScreen(),
        AppSection.budgetsPace => const BudgetsPaceScreen(),
        AppSection.campaigns => const SizedBox.shrink(),
      },
    );

    // С одного вложенного раздела на другой переходим заменой, чтобы не
    // копить их в стеке; из корня — обычным push, чтобы «назад» работало.
    if (current == AppSection.campaigns) {
      Navigator.of(context).push(route);
    } else {
      Navigator.of(context).pushReplacement(route);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final email = ref.watch(authProvider.select((s) => s.email));

    return Container(
      width: 220,
      decoration: const BoxDecoration(
        color: kSidebar,
        border: Border(right: BorderSide(color: kBorder)),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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
                          fontSize: 18,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'OmniBuy',
                    style: TextStyle(
                      color: kTextPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
            ),

            _NavItem(
              icon: Icons.campaign_outlined,
              label: 'Кампании',
              selected: current == AppSection.campaigns,
              onTap: () => _go(context, AppSection.campaigns),
            ),
            _NavItem(
              icon: Icons.space_dashboard_rounded,
              label: 'Сервисный дашборд',
              selected: current == AppSection.serviceDashboard,
              onTap: () => _go(context, AppSection.serviceDashboard),
            ),
            _NavItem(
              icon: Icons.speed_rounded,
              label: 'Бюджеты и темпы',
              selected: current == AppSection.budgetsPace,
              onTap: () => _go(context, AppSection.budgetsPace),
            ),

            const Spacer(),

            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: kBorder)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    email ?? 'Гость',
                    style: const TextStyle(
                      color: kTextPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 10),
                  TextButton.icon(
                    icon: const Icon(
                      Icons.logout,
                      size: 15,
                      color: kTextSecondary,
                    ),
                    label: const Text(
                      'Выйти',
                      style: TextStyle(color: kTextSecondary, fontSize: 13),
                    ),
                    onPressed: () => ref.read(authProvider.notifier).logout(),
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
    final color = selected ? kAccent : kTextSecondary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
          decoration: BoxDecoration(
            color: selected ? kAccentLight : Colors.transparent,
            border: Border(
              left: BorderSide(
                color: selected ? kAccent : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? kTextPrimary : kTextSecondary,
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
