import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/providers.dart';
import '../../app/subscription_provider.dart';
import '../../core/config/env.dart';
import '../../data/repositories/receipt_repository.dart';
import '../../core/money.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/category.dart';
import '../../data/models/monthly_review.dart';
import '../../data/models/receipt.dart';
import '../../data/models/subscription_tier.dart';
import '../../features/paywall/upgrade_gate.dart';
import 'analytics.dart';
import 'insights.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  static void _showAccountSheet(BuildContext context, WidgetRef ref) {
    final user = Supabase.instance.client.auth.currentUser;
    final isAnon = user == null || user.isAnonymous;
    final devProMode = !Env.hasRevenueCat;
    final display = user?.email ?? user?.phone ?? 'Guest account';

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: AppTheme.brand.withValues(alpha: 0.12),
                child: Icon(
                  isAnon ? Icons.person_outline : Icons.person,
                  color: AppTheme.brand,
                  size: 30,
                ),
              ),
              const SizedBox(height: 12),
              Text(display,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 4),
              Text(
                isAnon ? 'Anonymous session — data stays on this device' : 'Signed in',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
              ),
              if (devProMode) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.brand.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppTheme.brand.withValues(alpha: 0.3)),
                  ),
                  child: const Text(
                    '✓ Pro — all features unlocked (pre-launch mode)',
                    style: TextStyle(color: AppTheme.brand, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
              if (isAnon) ...[
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonal(
                    onPressed: () {
                      Navigator.pop(ctx);
                      context.push('/auth');
                    },
                    child: const Text('Create an account'),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await Supabase.instance.client.auth.signOut();
                    if (context.mounted) context.go('/auth');
                  },
                  child: const Text('Sign out',
                      style: TextStyle(color: Color(0xFFDC2626))),
                ),
              ),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (d) => AlertDialog(
                        title: const Text('Clear all data?'),
                        content: const Text(
                            'Removes all receipts and scan history '
                            'from this device. Cloud data (if any) is unaffected.\n\nThis cannot be undone.'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(d, false),
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(d, true),
                            style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFFDC2626)),
                            child: const Text('Clear'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed != true || !context.mounted) return;
                    await LocalReceiptRepository.clearAllData();
                    await ref.read(usageServiceProvider)?.clearAll();
                    ref.invalidate(receiptsProvider);
                  },
                  child: const Text('Clear all data',
                      style: TextStyle(color: Color(0xFFEA580C))),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currency = ref.watch(displayCurrencyProvider);
    final receiptsAsync = ref.watch(receiptsProvider);
    final selectedMonth = ref.watch(selectedDashboardMonthProvider);
    final reviewAsync = ref.watch(monthlyReviewProvider(selectedMonth));
    final caps = ref.watch(tierCapabilitiesProvider);
    final now = DateTime.now();
    final isCurrentMonth =
        selectedMonth.year == now.year && selectedMonth.month == now.month;

    return Scaffold(
      appBar: AppBar(
        title: const Text('ReceiptIQ'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.read(receiptsProvider.notifier).load(),
          ),
          IconButton(
            icon: const Icon(Icons.account_circle_outlined),
            onPressed: () => _showAccountSheet(context, ref),
          ),
        ],
      ),
      body: receiptsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (receipts) {
          final a = SpendingAnalytics.compute(receipts, now: selectedMonth);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
            children: [
              _MonthPicker(
                month: selectedMonth,
                isCurrentMonth: isCurrentMonth,
                onPrev: () => ref
                    .read(selectedDashboardMonthProvider.notifier)
                    .state = DateTime(
                        selectedMonth.year, selectedMonth.month - 1),
                onNext: isCurrentMonth
                    ? null
                    : () => ref
                        .read(selectedDashboardMonthProvider.notifier)
                        .state = DateTime(
                            selectedMonth.year, selectedMonth.month + 1),
              ),
              const SizedBox(height: 8),
              _MonthlyHero(amount: a.monthlySpend, currency: currency, trend: a.trendPercent),
              const SizedBox(height: 16),
              caps.aiMonthlyReview
                  ? _AiReviewCard(reviewAsync: reviewAsync)
                  : const UpgradeGate(
                      requiredTier: SubscriptionTier.starter,
                      featureName: 'AI Monthly Review',
                      child: SizedBox.shrink(),
                    ),
              const SizedBox(height: 16),
              _StatRow(analytics: a, currency: currency),
              const SizedBox(height: 16),
              if (a.byCategory.isNotEmpty) ...[
                _SectionTitle('Spending by category'),
                const SizedBox(height: 8),
                _CategoryBreakdown(analytics: a, currency: currency),
                const SizedBox(height: 16),
              ],
              _SectionTitle('Financial coach'),
              const SizedBox(height: 8),
              ...generateInsights(receipts, currency)
                  .map((i) => _InsightCard(insight: i)),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _SectionTitle('Recent receipts'),
                  TextButton(
                    onPressed: () => context.go('/receipts'),
                    child: const Text('See all'),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              ...() {
                final monthReceipts = receipts
                    .where((r) =>
                        r.date.year == selectedMonth.year &&
                        r.date.month == selectedMonth.month)
                    .toList();
                if (monthReceipts.isEmpty) {
                  return [
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(
                          child: Text('No receipts for this month.')),
                    )
                  ];
                }
                return monthReceipts
                    .take(4)
                    .map((r) => _RecentTile(receipt: r))
                    .toList();
              }(),
              const SizedBox(height: 8),
              Center(
                child: TextButton.icon(
                  onPressed: () => context.push('/history'),
                  icon: const Icon(Icons.history, size: 18),
                  label: const Text('View history'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _MonthPicker extends StatelessWidget {
  final DateTime month;
  final bool isCurrentMonth;
  final VoidCallback onPrev;
  final VoidCallback? onNext;
  const _MonthPicker({
    required this.month,
    required this.isCurrentMonth,
    required this.onPrev,
    this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final label = DateFormat.yMMMM().format(month);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          onPressed: onPrev,
          visualDensity: VisualDensity.compact,
        ),
        Text(label,
            style: const TextStyle(
                fontSize: 15, fontWeight: FontWeight.w700)),
        IconButton(
          icon: Icon(Icons.chevron_right,
              color: isCurrentMonth
                  ? const Color(0xFFCBD5E1)
                  : null),
          onPressed: onNext,
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);
  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
      );
}

class _MonthlyHero extends StatelessWidget {
  final double amount;
  final String currency;
  final double? trend;
  const _MonthlyHero(
      {required this.amount, required this.currency, this.trend});

  @override
  Widget build(BuildContext context) {
    final up = (trend ?? 0) >= 0;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppTheme.brand, AppTheme.brandDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('This month',
              style: TextStyle(color: Colors.white70, fontSize: 14)),
          const SizedBox(height: 6),
          Text(
            Money(amount, currency).format(),
            style: const TextStyle(
                color: Colors.white,
                fontSize: 34,
                fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          if (trend != null)
            Row(
              children: [
                Icon(up ? Icons.trending_up : Icons.trending_down,
                    color: Colors.white, size: 18),
                const SizedBox(width: 6),
                Text(
                  '${up ? 'Up' : 'Down'} ${trend!.abs().toStringAsFixed(0)}% vs last month',
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  final SpendingAnalytics analytics;
  final String currency;
  const _StatRow({required this.analytics, required this.currency});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            label: 'Biggest category',
            value: analytics.biggestCategory?.label ?? '—',
            sub: analytics.biggestCategory == null
                ? ''
                : Money(analytics.biggestCategoryAmount, currency).format(),
            icon: analytics.biggestCategory?.icon ?? Icons.category_outlined,
            color: analytics.biggestCategory?.color ?? AppTheme.brand,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            label: 'Avg / day',
            value: Money(analytics.averageDailySpend, currency).format(),
            sub: '${analytics.receiptCount} receipts',
            icon: Icons.calendar_today_outlined,
            color: AppTheme.accent,
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label, value, sub;
  final IconData icon;
  final Color color;
  const _StatCard({
    required this.label,
    required this.value,
    required this.sub,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 10),
            Text(label,
                style: const TextStyle(
                    color: Color(0xFF64748B), fontSize: 12)),
            const SizedBox(height: 2),
            Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w700)),
            if (sub.isNotEmpty)
              Text(sub,
                  style: const TextStyle(
                      color: Color(0xFF94A3B8), fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _CategoryBreakdown extends StatelessWidget {
  final SpendingAnalytics analytics;
  final String currency;
  const _CategoryBreakdown(
      {required this.analytics, required this.currency});

  @override
  Widget build(BuildContext context) {
    final entries = analytics.byCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = analytics.monthlySpend;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: entries.map((e) {
            final pct = total > 0 ? e.value / total : 0.0;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(e.key.icon, size: 18, color: e.key.color),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(e.key.label,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600))),
                      Text(Money(e.value, currency).format()),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: pct,
                      minHeight: 8,
                      backgroundColor: const Color(0xFFEFF1F5),
                      valueColor: AlwaysStoppedAnimation(e.key.color),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _InsightCard extends StatelessWidget {
  final Insight insight;
  const _InsightCard({required this.insight});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: insight.color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: insight.color.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(insight.icon, color: insight.color, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(insight.message,
                style: const TextStyle(fontSize: 14, height: 1.35)),
          ),
        ],
      ),
    );
  }
}

class _RecentTile extends StatelessWidget {
  final Receipt receipt;
  const _RecentTile({required this.receipt});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: () => context.push('/receipt/${receipt.id}'),
        leading: CircleAvatar(
          backgroundColor: receipt.category.color.withValues(alpha: 0.15),
          child: Icon(receipt.category.icon, color: receipt.category.color),
        ),
        title: Text(receipt.merchant,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(receipt.category.label),
        trailing: Text(receipt.total.format(),
            style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }
}

class _AiReviewCard extends StatelessWidget {
  final AsyncValue<MonthlyReview?> reviewAsync;
  const _AiReviewCard({required this.reviewAsync});

  @override
  Widget build(BuildContext context) {
    return reviewAsync.when(
      loading: () => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppTheme.brand.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(width: 12),
              const Text('Generating your monthly review…',
                  style: TextStyle(color: Color(0xFF64748B))),
            ],
          ),
        ),
      ),
      error: (_, _) => const SizedBox.shrink(),
      data: (review) {
        if (review == null) return const SizedBox.shrink();
        return GestureDetector(
          onTap: () => context.push('/review/monthly'),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.auto_awesome,
                          size: 18, color: AppTheme.brand),
                      const SizedBox(width: 8),
                      const Text('AI Monthly Review',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.brand)),
                      const Spacer(),
                      const Icon(Icons.chevron_right,
                          size: 18, color: Color(0xFF94A3B8)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    review.headline,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600, height: 1.3),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
