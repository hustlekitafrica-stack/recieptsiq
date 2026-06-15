import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/providers.dart';
import '../../app/subscription_provider.dart';
import '../../core/money.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/category.dart';
import '../../data/models/monthly_review.dart';
import '../../data/models/receipt.dart';
import '../../data/models/subscription_tier.dart';
import '../../features/dashboard/analytics.dart';
import '../../features/dashboard/insights.dart';
import '../../features/paywall/upgrade_gate.dart';

class HistoryMonthDetailScreen extends ConsumerWidget {
  final String yearMonth;
  const HistoryMonthDetailScreen({super.key, required this.yearMonth});

  DateTime get _month {
    final parts = yearMonth.split('-');
    return DateTime(int.parse(parts[0]), int.parse(parts[1]));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = _month;
    final label = DateFormat.yMMMM().format(month);
    final receiptsAsync = ref.watch(receiptsProvider);
    final currency = ref.watch(displayCurrencyProvider);
    final reviewAsync = ref.watch(monthlyReviewProvider(month));
    final caps = ref.watch(tierCapabilitiesProvider);

    return Scaffold(
      appBar: AppBar(title: Text(label)),
      body: receiptsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (allReceipts) {
          final receipts = allReceipts
              .where((r) =>
                  r.date.year == month.year && r.date.month == month.month)
              .toList();

          if (receipts.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text('No receipts for this month.',
                    style: TextStyle(color: Color(0xFF94A3B8))),
              ),
            );
          }

          final analytics = SpendingAnalytics.compute(allReceipts, now: month);
          final insights = generateInsights(allReceipts.where((r) =>
              r.date.year == month.year && r.date.month == month.month).toList(), currency);

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              // ── Hero ────────────────────────────────────────────────────
              _Hero(
                  amount: analytics.monthlySpend,
                  currency: currency,
                  trend: analytics.trendPercent),
              const SizedBox(height: 16),
              // ── AI Review ───────────────────────────────────────────────
              caps.aiMonthlyReview
                  ? _AiReviewCard(
                      reviewAsync: reviewAsync, monthLabel: label)
                  : UpgradeGate(
                      requiredTier: SubscriptionTier.starter,
                      featureName: 'AI Monthly Review',
                      child: const SizedBox.shrink(),
                    ),
              const SizedBox(height: 16),
              // ── Stats row ───────────────────────────────────────────────
              _StatsRow(analytics: analytics, currency: currency),
              const SizedBox(height: 16),
              // ── Category breakdown ──────────────────────────────────────
              if (analytics.byCategory.isNotEmpty) ...[
                const _Title('Spending by category'),
                const SizedBox(height: 8),
                _CategoryBreakdown(
                    analytics: analytics, currency: currency),
                const SizedBox(height: 16),
              ],
              // ── Insights ────────────────────────────────────────────────
              if (insights.isNotEmpty) ...[
                const _Title('Insights'),
                const SizedBox(height: 8),
                ...insights.map((i) => _InsightCard(insight: i)),
                const SizedBox(height: 16),
              ],
              // ── Receipts list ───────────────────────────────────────────
              const _Title('Receipts'),
              const SizedBox(height: 8),
              ...receipts.map((r) => _ReceiptTile(receipt: r)),
            ],
          );
        },
      ),
    );
  }
}

// ── Hero ──────────────────────────────────────────────────────────────────────

class _Hero extends StatelessWidget {
  final double amount;
  final String currency;
  final double? trend;
  const _Hero(
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
          const Text('Total spending',
              style: TextStyle(color: Colors.white70, fontSize: 14)),
          const SizedBox(height: 6),
          Text(
            Money(amount, currency).format(),
            style: const TextStyle(
                color: Colors.white,
                fontSize: 34,
                fontWeight: FontWeight.w800),
          ),
          if (trend != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(up ? Icons.trending_up : Icons.trending_down,
                    color: Colors.white, size: 18),
                const SizedBox(width: 6),
                Text(
                  '${up ? 'Up' : 'Down'} ${trend!.abs().toStringAsFixed(0)}% vs prior month',
                  style: const TextStyle(
                      color: Colors.white, fontSize: 13),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ── AI Review Card ────────────────────────────────────────────────────────────

class _AiReviewCard extends StatelessWidget {
  final AsyncValue<MonthlyReview?> reviewAsync;
  final String monthLabel;
  const _AiReviewCard(
      {required this.reviewAsync, required this.monthLabel});

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
              const Text('Generating review…',
                  style: TextStyle(color: Color(0xFF64748B))),
            ],
          ),
        ),
      ),
      error: (_, __) => const SizedBox.shrink(),
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
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        height: 1.3),
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

// ── Stats Row ─────────────────────────────────────────────────────────────────

class _StatsRow extends StatelessWidget {
  final SpendingAnalytics analytics;
  final String currency;
  const _StatsRow({required this.analytics, required this.currency});

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

// ── Category Breakdown ────────────────────────────────────────────────────────

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

// ── Insight Card ──────────────────────────────────────────────────────────────

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

// ── Receipt Tile ──────────────────────────────────────────────────────────────

class _ReceiptTile extends StatelessWidget {
  final Receipt receipt;
  const _ReceiptTile({required this.receipt});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: () => context.push('/receipt/${receipt.id}'),
        leading: CircleAvatar(
          backgroundColor:
              receipt.category.color.withValues(alpha: 0.15),
          child: Icon(receipt.category.icon,
              color: receipt.category.color),
        ),
        title: Text(receipt.merchant,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
            '${receipt.category.label} · ${DateFormat.MMMd().format(receipt.date)}'),
        trailing: Text(receipt.total.format(),
            style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }
}

// ── Section title ─────────────────────────────────────────────────────────────

class _Title extends StatelessWidget {
  final String text;
  const _Title(this.text);
  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
      );
}
