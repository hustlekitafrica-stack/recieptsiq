import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/providers.dart';
import '../../app/subscription_provider.dart';
import '../../data/repositories/receipt_repository.dart';
import '../../core/money.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/monthly_review.dart';
import '../../data/models/receipt.dart';
import '../../data/models/subscription_tier.dart';
import '../../features/budgets/budget_model.dart';
import '../../features/budgets/budget_provider.dart';
import '../../features/leaks/money_leak_detector.dart';
import '../../features/paywall/upgrade_gate.dart';
import 'analytics.dart';
import 'health_score.dart';
import 'insights.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  static void _showAccountSheet(BuildContext context, WidgetRef ref) {
    User? user;
    try { user = Supabase.instance.client.auth.currentUser; } catch (_) {}
    final isAnon = user == null || user.isAnonymous;
    final display = user?.email ?? user?.phone ?? 'Guest account';

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Consumer(
        builder: (ctx, sheetRef, _) {
          final subAsync = sheetRef.watch(userSubscriptionRecordProvider);
          return SafeArea(
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
              if (!isAnon) ...[
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      context.push('/paywall');
                    },
                    icon: const Icon(Icons.rocket_launch_outlined, size: 16),
                    label: const Text('View plans'),
                  ),
                ),
                subAsync.when(
                  data: (sub) {
                    if (sub == null) return const SizedBox.shrink();
                    final isPesapal = sub['payment_provider'] == 'pesapal';
                    final autoRenew = sub['auto_renew'] == true;
                    if (!isPesapal || !autoRenew) return const SizedBox.shrink();
                    final period = (sub['billing_period'] ?? 'monthly') as String;
                    final expiresAt = sub['expires_at'] != null
                        ? DateTime.tryParse(sub['expires_at'] as String)
                        : null;
                    final expiresStr = expiresAt != null
                        ? DateFormat('MMM d, yyyy').format(expiresAt.toLocal())
                        : null;
                    return Column(
                      children: [
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0FDF4),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFF86EFAC)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.autorenew, size: 15, color: Color(0xFF16A34A)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Pesapal · ${period[0].toUpperCase()}${period.substring(1)}'
                                  '${expiresStr != null ? ' · renews $expiresStr' : ''}',
                                  style: const TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF15803D),
                                      fontWeight: FontWeight.w500),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () => _cancelSubscription(ctx, sheetRef),
                            icon: const Icon(Icons.cancel_outlined, size: 16),
                            label: const Text('Cancel subscription'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFFDC2626),
                              side: const BorderSide(color: Color(0xFFDC2626)),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
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
      );
        },
      ),
    );
  }

  static Future<void> _cancelSubscription(
      BuildContext ctx, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: ctx,
      builder: (d) => AlertDialog(
        title: const Text('Cancel subscription?'),
        content: const Text(
            'Your subscription stays active until the end of the current billing period.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: const Text('Keep subscription'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(d, true),
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626)),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (confirmed != true || !ctx.mounted) return;
    try {
      await Supabase.instance.client.functions
          .invoke('payments-pesapal-cancel');
      ref.invalidate(userSubscriptionRecordProvider);
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          const SnackBar(
              content: Text(
                  'Subscription cancelled — access continues until expiry.')),
        );
        Navigator.pop(ctx);
      }
    } catch (e) {
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(content: Text('Failed to cancel: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    User? user;
    try { user = Supabase.instance.client.auth.currentUser; } catch (_) {}
    final currency = ref.watch(displayCurrencyProvider);
    final receiptsAsync = ref.watch(receiptsProvider);
    final selectedMonth = ref.watch(selectedDashboardMonthProvider);
    final reviewAsync = ref.watch(monthlyReviewProvider(selectedMonth));
    final caps = ref.watch(tierCapabilitiesProvider);
    final budgetAsync = ref.watch(budgetProvider);
    final now = DateTime.now();
    final isCurrentMonth =
        selectedMonth.year == now.year && selectedMonth.month == now.month;

    return Scaffold(
      appBar: AppBar(
        title: _GreetingTitle(user: user),
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
          final budget = budgetAsync.valueOrNull;
          final healthScore = BusinessHealthScore.compute(
            receipts,
            monthlyBudget: budget?.amount,
          );
          final leaks = isCurrentMonth
              ? MoneyLeakDetector.detect(receipts, currency)
              : <MoneyLeak>[];

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
              _DualHero(analytics: a, currency: currency),
              const SizedBox(height: 12),
              _HealthScoreCard(
                score: healthScore,
                onBudgetTap: () => context.push('/budget'),
              ),
              if (budget != null && isCurrentMonth) ...[
                const SizedBox(height: 12),
                _BudgetCard(
                    budget: budget, spent: a.monthlySpend, currency: currency),
              ],
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
              if (leaks.isNotEmpty) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _SectionTitle('Money leaks'),
                    TextButton(
                      onPressed: () => context.push('/leaks'),
                      child: const Text('See all'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ...leaks.take(2).map((l) => _LeakPreviewCard(leak: l)),
                const SizedBox(height: 16),
              ] else ...[
                _SectionTitle('Financial coach'),
                const SizedBox(height: 8),
                ...generateInsights(receipts, currency)
                    .map((i) => _InsightCard(insight: i)),
                const SizedBox(height: 16),
              ],
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


class _StatRow extends StatelessWidget {
  final SpendingAnalytics analytics;
  final String currency;
  const _StatRow({required this.analytics, required this.currency});

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
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
      ),
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

// ── New dashboard widgets ─────────────────────────────────────────────────────

class _GreetingTitle extends StatelessWidget {
  final User? user;
  const _GreetingTitle({required this.user});

  String _name() {
    if (user == null || user!.isAnonymous) return 'there';
    final meta = user!.userMetadata;
    if (meta?['full_name'] != null) {
      return (meta!['full_name'] as String).split(' ').first;
    }
    final email = user!.email;
    if (email != null && email.contains('@')) return email.split('@').first;
    final phone = user!.phone;
    if (phone != null && phone.length >= 6) {
      return '${phone.substring(0, 4)}…';
    }
    return 'there';
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      '${_greeting()}, ${_name()}',
      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
    );
  }
}

class _DualHero extends StatelessWidget {
  final SpendingAnalytics analytics;
  final String currency;
  const _DualHero({required this.analytics, required this.currency});

  @override
  Widget build(BuildContext context) {
    final savings = (analytics.lastMonthSpend - analytics.monthlySpend)
        .clamp(0.0, double.infinity);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppTheme.brand, AppTheme.brandDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('This month',
                      style: TextStyle(color: Colors.white70, fontSize: 13)),
                  const SizedBox(height: 4),
                  Text(
                    Money(analytics.monthlySpend, currency).format(),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  if (analytics.trendPercent != null)
                    Row(
                      children: [
                        Icon(
                          (analytics.trendPercent ?? 0) >= 0
                              ? Icons.trending_up
                              : Icons.trending_down,
                          color: Colors.white70,
                          size: 14,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${(analytics.trendPercent ?? 0) >= 0 ? '+' : ''}${analytics.trendPercent!.toStringAsFixed(0)}% vs last month',
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 11),
                        ),
                      ],
                    )
                  else
                    const Text('No prior month',
                        style: TextStyle(color: Colors.white38, fontSize: 11)),
                ],
              ),
            ),
            Container(
              width: 1,
              margin: const EdgeInsets.symmetric(horizontal: 16),
              color: Colors.white24,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('You saved',
                      style: TextStyle(color: Colors.white70, fontSize: 13)),
                  const SizedBox(height: 4),
                  Text(
                    Money(savings, currency).format(),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    savings > 0
                        ? 'vs last month 🎉'
                        : analytics.lastMonthSpend == 0
                            ? 'No data to compare yet'
                            : 'Try to reduce costs',
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 11),
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

class _HealthScoreCard extends ConsumerWidget {
  final BusinessHealthScore score;
  final VoidCallback onBudgetTap;
  const _HealthScoreCard(
      {required this.score, required this.onBudgetTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final caps = ref.watch(tierCapabilitiesProvider);
    if (!score.hasData) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.brand.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.bar_chart_outlined,
                    color: AppTheme.brand, size: 22),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Business Health Score',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 14)),
                    SizedBox(height: 3),
                    Text(
                      'Scan at least 5 receipts to unlock your score',
                      style:
                          TextStyle(color: Color(0xFF64748B), fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Business Health',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 14)),
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${score.score}',
                          style: TextStyle(
                              fontSize: 40,
                              fontWeight: FontWeight.w900,
                              color: score.gradeColor),
                        ),
                        const Padding(
                          padding: EdgeInsets.only(bottom: 7),
                          child: Text('/100',
                              style: TextStyle(
                                  fontSize: 15, color: Color(0xFF94A3B8))),
                        ),
                      ],
                    ),
                  ],
                ),
                const Spacer(),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: score.gradeColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        score.grade,
                        style: TextStyle(
                            color: score.gradeColor,
                            fontWeight: FontWeight.w700,
                            fontSize: 13),
                      ),
                    ),
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: onBudgetTap,
                      child: const Text(
                        'Set budget →',
                        style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.brand,
                            fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 10),
            if (caps.fullHealthScore)
              ...score.pillars.map(
                (p) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Icon(
                        p.good
                            ? Icons.check_circle_outline
                            : Icons.warning_amber_outlined,
                        size: 16,
                        color: p.good
                            ? const Color(0xFF22C55E)
                            : const Color(0xFFF59E0B),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(p.label,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13)),
                      ),
                      Text(p.description,
                          style: const TextStyle(
                              color: Color(0xFF94A3B8), fontSize: 12)),
                    ],
                  ),
                ),
              )
            else
              GestureDetector(
                onTap: () => context.push('/paywall'),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                  decoration: BoxDecoration(
                    color: AppTheme.brand.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.lock_outline, size: 15, color: AppTheme.brand),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Upgrade to Starter to see full pillar breakdown',
                          style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.brand,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                      Icon(Icons.chevron_right, size: 16, color: AppTheme.brand),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BudgetCard extends StatelessWidget {
  final Budget budget;
  final double spent;
  final String currency;
  const _BudgetCard({
    required this.budget,
    required this.spent,
    required this.currency,
  });

  @override
  Widget build(BuildContext context) {
    final pct = (spent / budget.amount).clamp(0.0, 1.5);
    final pctDisplay = (pct * 100).toStringAsFixed(0);
    final remaining = budget.amount - spent;
    final isOver = spent > budget.amount;
    final color = pct >= 1.0
        ? const Color(0xFFEF4444)
        : pct >= 0.75
            ? const Color(0xFFF59E0B)
            : const Color(0xFF22C55E);
    final now = DateTime.now();
    final daysInMonth =
        DateTime(now.year, now.month + 1, 0).day;
    final daysLeft = daysInMonth - now.day;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.savings_outlined, color: color, size: 18),
                const SizedBox(width: 8),
                const Text('Monthly Budget',
                    style: TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 14)),
                const Spacer(),
                GestureDetector(
                  onTap: () => context.push('/budget'),
                  child: const Text('Edit',
                      style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.brand,
                          fontWeight: FontWeight.w500)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(Money(spent, currency).format(),
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15)),
                Text('of ${Money(budget.amount, currency).format()}',
                    style: const TextStyle(
                        color: Color(0xFF94A3B8), fontSize: 13)),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: pct.clamp(0.0, 1.0),
                minHeight: 10,
                backgroundColor: const Color(0xFFEFF1F5),
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$pctDisplay% used',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: color),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isOver
                        ? 'Over by ${Money(spent - budget.amount, currency).format()}'
                        : '${Money(remaining, currency).format()} left · $daysLeft days remaining',
                    style: const TextStyle(
                        color: Color(0xFF64748B), fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LeakPreviewCard extends StatelessWidget {
  final MoneyLeak leak;
  const _LeakPreviewCard({required this.leak});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: leak.color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: leak.color.withValues(alpha: 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(leak.icon, color: leak.color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(leak.title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 3),
                Text(
                  leak.detail,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF64748B),
                      height: 1.3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
