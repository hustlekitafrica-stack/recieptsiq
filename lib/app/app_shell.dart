import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/app_theme.dart';

/// Bottom-navigation shell with a central Scan button.
class AppShell extends StatelessWidget {
  final Widget child;
  const AppShell({super.key, required this.child});

  static const _tabs = ['/dashboard', '/receipts', '/budgets', '/search'];

  int _indexFor(String location) {
    final i = _tabs.indexWhere((t) => location.startsWith(t));
    return i < 0 ? 0 : i;
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    final index = _indexFor(location);

    return Scaffold(
      body: child,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/scan'),
        backgroundColor: AppTheme.brand,
        foregroundColor: Colors.white,
        elevation: 2,
        shape: const CircleBorder(),
        child: const Icon(Icons.document_scanner_outlined, size: 28),
      ),
      bottomNavigationBar: BottomAppBar(
        height: 68,
        color: Colors.white,
        elevation: 8,
        shape: const CircularNotchedRectangle(),
        notchMargin: 8,
        padding: EdgeInsets.zero,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _NavItem(
              icon: Icons.dashboard_outlined,
              activeIcon: Icons.dashboard,
              label: 'Home',
              selected: index == 0,
              onTap: () => context.go('/dashboard'),
            ),
            _NavItem(
              icon: Icons.receipt_long_outlined,
              activeIcon: Icons.receipt_long,
              label: 'Receipts',
              selected: index == 1,
              onTap: () => context.go('/receipts'),
            ),
            const SizedBox(width: 48),
            _NavItem(
              icon: Icons.pie_chart_outline,
              activeIcon: Icons.pie_chart,
              label: 'Budgets',
              selected: index == 2,
              onTap: () => context.go('/budgets'),
            ),
            _NavItem(
              icon: Icons.search_outlined,
              activeIcon: Icons.search,
              label: 'Search',
              selected: index == 3,
              onTap: () => context.go('/search'),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppTheme.brand : const Color(0xFF94A3B8);
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(selected ? activeIcon : icon, color: color, size: 24),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
