import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/providers.dart';
import '../../app/subscription_provider.dart';
import '../../core/money.dart';
import '../../core/theme/app_theme.dart';
import 'money_leak_detector.dart';

class LeaksScreen extends ConsumerWidget {
  const LeaksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final receiptsAsync = ref.watch(receiptsProvider);
    final currency = ref.watch(displayCurrencyProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Money Leak Detector')),
      body: receiptsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (receipts) {
          final leaks =
              MoneyLeakDetector.detect(receipts, currency);

          if (leaks.isEmpty) {
            return _EmptyState();
          }

          final totalSaving =
              leaks.fold<double>(0, (s, l) => s + l.savingAmount);

          final caps = ref.read(tierCapabilitiesProvider);
          final maxShown = caps.isUnlimitedLeaks
              ? leaks.length
              : caps.maxLeaksShown.clamp(0, leaks.length);
          final locked = leaks.length - maxShown;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
            children: [
              _SavingsBanner(
                  totalSaving: totalSaving, currency: currency),
              const SizedBox(height: 16),
              const _SectionLabel('Detected leaks this month'),
              const SizedBox(height: 8),
              ...leaks
                  .take(maxShown)
                  .map((l) => _LeakCard(leak: l, currency: currency)),
              if (locked > 0) _LeakUpgradeTeaser(lockedCount: locked),
              const SizedBox(height: 16),
              _HowItWorksCard(),
            ],
          );
        },
      ),
    );
  }
}

class _SavingsBanner extends StatelessWidget {
  final double totalSaving;
  final String currency;
  const _SavingsBanner({required this.totalSaving, required this.currency});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFEF4444), Color(0xFFB91C1C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded,
              color: Colors.white, size: 32),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Potential savings found',
                    style: TextStyle(
                        color: Colors.white70,
                        fontSize: 13)),
                const SizedBox(height: 4),
                Text(
                  Money(totalSaving, currency).format(),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                const Text('estimated per month',
                    style: TextStyle(
                        color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LeakCard extends StatelessWidget {
  final MoneyLeak leak;
  final String currency;
  const _LeakCard({required this.leak, required this.currency});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: leak.color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            decoration: BoxDecoration(
              color: leak.color.withValues(alpha: 0.07),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: leak.color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(leak.icon, color: leak.color, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(leak.title,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 14)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: leak.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '~${Money(leak.savingAmount, currency).format()}',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: leak.color),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(leak.detail,
                    style: const TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        color: Color(0xFF374151))),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.lightbulb_outline,
                        size: 14, color: AppTheme.brand),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(leak.actionHint,
                          style: const TextStyle(
                              fontSize: 12,
                              color: AppTheme.brand,
                              fontWeight: FontWeight.w500)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700));
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline,
                size: 56, color: Color(0xFF22C55E)),
            SizedBox(height: 14),
            Text('No leaks detected',
                style:
                    TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
            SizedBox(height: 8),
            Text(
              'Your spending looks clean this month. Keep scanning receipts to get more detailed insights.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}

class _HowItWorksCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.info_outline,
                    size: 16, color: Color(0xFF94A3B8)),
                SizedBox(width: 6),
                Text('About estimates',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF94A3B8),
                        fontSize: 13)),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Potential savings are estimates based on your spending patterns. '
              'Frequency savings assume a ~12% bulk discount; price drift is based on '
              'month-over-month average receipt totals per supplier.',
              style: TextStyle(
                  fontSize: 12,
                  color: Color(0xFF94A3B8),
                  height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _LeakUpgradeTeaser extends StatelessWidget {
  final int lockedCount;
  const _LeakUpgradeTeaser({required this.lockedCount});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.brand.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.lock_outline, color: AppTheme.brand, size: 26),
            ),
            const SizedBox(height: 12),
            Text(
              '$lockedCount more leak${lockedCount > 1 ? 's' : ''} detected',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
            const SizedBox(height: 6),
            const Text(
              'Upgrade to Starter to see all leaks and unlock your full savings potential.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: () {
                bool isAnon = true;
                try {
                  final u = Supabase.instance.client.auth.currentUser;
                  isAnon = u == null || u.isAnonymous;
                } catch (_) {}
                context.push(isAnon ? '/auth' : '/paywall');
              },
              icon: const Icon(Icons.rocket_launch_outlined, size: 18),
              label: const Text('Upgrade to Starter'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 44),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
