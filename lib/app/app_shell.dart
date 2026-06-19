import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/app_theme.dart';

/// Bottom-navigation shell with a central Scan button.
class AppShell extends StatefulWidget {
  final Widget child;
  const AppShell({super.key, required this.child});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  late final Animation<double> _scale;

  static const _tabs = ['/dashboard', '/receipts', '/analytics', '/search'];

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _scale = Tween<double>(begin: 1.0, end: 1.10).animate(
      CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  int _indexFor(String location) {
    final i = _tabs.indexWhere((t) => location.startsWith(t));
    return i < 0 ? 0 : i;
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    final index = _indexFor(location);

    return Scaffold(
      body: widget.child,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: ScaleTransition(
        scale: _scale,
        child: FloatingActionButton(
          onPressed: () => context.push('/scan'),
          backgroundColor: AppTheme.brand,
          foregroundColor: Colors.white,
          elevation: 2,
          shape: const CircleBorder(),
          child: const Icon(Icons.document_scanner_outlined, size: 28),
        ),
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
              icon: Icons.bar_chart_outlined,
              activeIcon: Icons.bar_chart,
              label: 'Analytics',
              selected: index == 2,
              onTap: () => context.go('/analytics'),
            ),
            _NavItem(
              icon: Icons.smart_toy_outlined,
              activeIcon: Icons.smart_toy,
              label: 'Assistant',
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
