import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/providers.dart';
import '../../core/money.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/yearly_review.dart';
import '../../features/dashboard/analytics.dart';

class YearlyReviewScreen extends ConsumerWidget {
  final int year;
  const YearlyReviewScreen({super.key, required this.year});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reviewAsync = ref.watch(yearlyReviewProvider(year));
    final receiptsAsync = ref.watch(receiptsProvider);
    final currency = ref.watch(displayCurrencyProvider);

    return Scaffold(
      appBar: AppBar(title: Text('$year Year in Review')),
      body: receiptsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (allReceipts) {
          final analytics = YearlyAnalytics.compute(allReceipts, year);

          if (analytics.receiptCount == 0) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text('No receipts in this year.',
                    style: TextStyle(color: Color(0xFF94A3B8))),
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              // ── Annual hero ─────────────────────────────────────────────
              _AnnualHero(analytics: analytics, currency: currency),
              const SizedBox(height: 16),
              // ── AI narrative ────────────────────────────────────────────
              _AiCard(reviewAsync: reviewAsync),
              const SizedBox(height: 16),
              // ── Month-by-month chart ────────────────────────────────────
              const _Title('Month by month'),
              const SizedBox(height: 10),
              _MonthBarChart(analytics: analytics, currency: currency),
              const SizedBox(height: 16),
              // ── Top categories ──────────────────────────────────────────
              if (analytics.byCategory.isNotEmpty) ...[
                const _Title('Spending by category'),
                const SizedBox(height: 8),
                _CategoryBreakdown(
                    analytics: analytics, currency: currency),
                const SizedBox(height: 16),
              ],
              // ── Best & Worst months ─────────────────────────────────────
              _BestWorstRow(analytics: analytics, currency: currency),
              const SizedBox(height: 16),
              // ── Top merchants ───────────────────────────────────────────
              if (analytics.topMerchants.isNotEmpty) ...[
                const _Title('Top merchants'),
                const SizedBox(height: 8),
                _TopMerchants(
                    merchants: analytics.topMerchants,
                    currency: currency),
                const SizedBox(height: 16),
              ],
              // ── Savings opportunities ───────────────────────────────────
              _SavingsSection(
                  analytics: analytics,
                  reviewAsync: reviewAsync,
                  currency: currency),
            ],
          );
        },
      ),
    );
  }
}

// ── Annual Hero ───────────────────────────────────────────────────────────────

class _AnnualHero extends StatelessWidget {
  final YearlyAnalytics analytics;
  final String currency;
  const _AnnualHero({required this.analytics, required this.currency});

  @override
  Widget build(BuildContext context) {
    final yoy = analytics.yearOverYearChange;
    final up = (yoy ?? 0) >= 0;
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
          Text('${analytics.year} total spending',
              style: const TextStyle(color: Colors.white70, fontSize: 14)),
          const SizedBox(height: 6),
          Text(
            Money(analytics.totalSpend, currency).format(),
            style: const TextStyle(
                color: Colors.white,
                fontSize: 34,
                fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            '${analytics.receiptCount} receipts',
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          if (yoy != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(up ? Icons.trending_up : Icons.trending_down,
                    color: Colors.white, size: 18),
                const SizedBox(width: 6),
                Text(
                  '${up ? 'Up' : 'Down'} ${yoy.abs().toStringAsFixed(1)}% vs ${analytics.year - 1}',
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

// ── AI Card ───────────────────────────────────────────────────────────────────

class _AiCard extends StatelessWidget {
  final AsyncValue<YearlyReview?> reviewAsync;
  const _AiCard({required this.reviewAsync});

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
              const Text('Generating year-in-review…',
                  style: TextStyle(color: Color(0xFF64748B))),
            ],
          ),
        ),
      ),
      error: (_, __) => const SizedBox.shrink(),
      data: (review) {
        if (review == null || review.headline.isEmpty) {
          return const SizedBox.shrink();
        }
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: const [
                    Icon(Icons.auto_awesome,
                        size: 18, color: AppTheme.brand),
                    SizedBox(width: 8),
                    Text('AI Year in Review',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.brand)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(review.headline,
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        height: 1.25)),
                if (review.summary.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(review.summary,
                      style: const TextStyle(
                          fontSize: 14,
                          height: 1.5,
                          color: Color(0xFF475569))),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

// ── Month Bar Chart ───────────────────────────────────────────────────────────

class _MonthBarChart extends StatelessWidget {
  final YearlyAnalytics analytics;
  final String currency;
  const _MonthBarChart(
      {required this.analytics, required this.currency});

  static const _monthNames = [
    '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  @override
  Widget build(BuildContext context) {
    final totals = analytics.monthlyTotals;
    if (totals.isEmpty) return const SizedBox.shrink();
    final maxVal =
        totals.values.reduce((a, b) => math.max(a, b));

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          children: List.generate(12, (i) {
            final month = i + 1;
            final val = totals[month] ?? 0;
            final pct = maxVal > 0 ? val / maxVal : 0.0;
            final isWorst = month == analytics.worstMonth && val > 0;
            final isBest = month == analytics.bestMonth && val > 0;
            final barColor = isWorst
                ? const Color(0xFFEF4444)
                : isBest
                    ? AppTheme.accent
                    : AppTheme.brand;

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 32,
                    child: Text(_monthNames[month],
                        style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF64748B),
                            fontWeight: FontWeight.w500)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: pct,
                        minHeight: 20,
                        backgroundColor: const Color(0xFFEFF1F5),
                        valueColor: AlwaysStoppedAnimation(
                            barColor.withValues(alpha: 0.85)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 72,
                    child: Text(
                      val > 0 ? Money(val, currency).format() : '—',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: isWorst || isBest
                              ? FontWeight.w700
                              : FontWeight.w400,
                          color: isWorst
                              ? const Color(0xFFEF4444)
                              : isBest
                                  ? AppTheme.accent
                                  : const Color(0xFF475569)),
                    ),
                  ),
                ],
              ),
            );
          }),
        ),
      ),
    );
  }
}

// ── Category Breakdown ────────────────────────────────────────────────────────

class _CategoryBreakdown extends StatelessWidget {
  final YearlyAnalytics analytics;
  final String currency;
  const _CategoryBreakdown(
      {required this.analytics, required this.currency});

  @override
  Widget build(BuildContext context) {
    final entries = analytics.byCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = analytics.totalSpend;
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
                      valueColor:
                          AlwaysStoppedAnimation(e.key.color),
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

// ── Best & Worst months ───────────────────────────────────────────────────────

class _BestWorstRow extends StatelessWidget {
  final YearlyAnalytics analytics;
  final String currency;
  const _BestWorstRow(
      {required this.analytics, required this.currency});

  static const _monthNames = [
    '', 'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  @override
  Widget build(BuildContext context) {
    final bestAmt = analytics.monthlyTotals[analytics.bestMonth] ?? 0;
    final worstAmt = analytics.monthlyTotals[analytics.worstMonth] ?? 0;
    return Row(
      children: [
        Expanded(
          child: _HighlightCard(
            label: 'Best month',
            month: _monthNames[analytics.bestMonth],
            amount: Money(bestAmt, currency).format(),
            icon: Icons.sentiment_satisfied_outlined,
            color: AppTheme.accent,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _HighlightCard(
            label: 'Highest spend',
            month: _monthNames[analytics.worstMonth],
            amount: Money(worstAmt, currency).format(),
            icon: Icons.warning_amber_outlined,
            color: const Color(0xFFF59E0B),
          ),
        ),
      ],
    );
  }
}

class _HighlightCard extends StatelessWidget {
  final String label, month, amount;
  final IconData icon;
  final Color color;
  const _HighlightCard({
    required this.label,
    required this.month,
    required this.amount,
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
            Text(month,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700)),
            Text(amount,
                style: TextStyle(
                    color: color,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

// ── Top Merchants ─────────────────────────────────────────────────────────────

class _TopMerchants extends StatelessWidget {
  final Map<String, double> merchants;
  final String currency;
  const _TopMerchants(
      {required this.merchants, required this.currency});

  @override
  Widget build(BuildContext context) {
    final entries = merchants.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: entries.take(5).map((e) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppTheme.brand.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(
                      child: Text(
                        e.key.isNotEmpty
                            ? e.key[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                            color: AppTheme.brand,
                            fontWeight: FontWeight.w800,
                            fontSize: 15),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Text(e.key,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600))),
                  Text(Money(e.value, currency).format(),
                      style: const TextStyle(
                          fontWeight: FontWeight.w700)),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

// ── Savings Opportunities ─────────────────────────────────────────────────────

class _SavingsSection extends StatelessWidget {
  final YearlyAnalytics analytics;
  final AsyncValue<YearlyReview?> reviewAsync;
  final String currency;
  const _SavingsSection({
    required this.analytics,
    required this.reviewAsync,
    required this.currency,
  });

  List<String> _ruleBased() {
    final tips = <String>[];
    final sorted = analytics.byCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (sorted.isNotEmpty && analytics.totalSpend > 0) {
      final top = sorted.first;
      final pct = (top.value / analytics.totalSpend * 100).round();
      if (pct >= 30) {
        tips.add(
            '${top.key.label} was your biggest expense at $pct% of annual spend (${Money(top.value, currency).format()}). Review if this aligns with your priorities.');
      }
    }
    if (analytics.topMerchants.isNotEmpty) {
      final topM = analytics.topMerchants.entries.first;
      tips.add(
          'You spent ${Money(topM.value, currency).format()} at ${topM.key} this year — your single biggest merchant.');
    }
    if (analytics.yearOverYearChange != null &&
        analytics.yearOverYearChange! > 15) {
      tips.add(
          'Spending grew ${analytics.yearOverYearChange!.toStringAsFixed(1)}% vs ${analytics.year - 1}. Review recurring expenses to find savings.');
    }
    return tips;
  }

  @override
  Widget build(BuildContext context) {
    final aiTips = reviewAsync.valueOrNull?.savingsOpportunities ?? [];
    final ruleTips = _ruleBased();
    final all = {...aiTips, ...ruleTips}.toList();
    if (all.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Title('Savings opportunities'),
        const SizedBox(height: 8),
        ...all.map((t) => _TipCard(text: t)),
      ],
    );
  }
}

class _TipCard extends StatelessWidget {
  final String text;
  const _TipCard({required this.text});
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.accent.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: AppTheme.accent.withValues(alpha: 0.20)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 6),
            width: 6,
            height: 6,
            decoration: BoxDecoration(
                color: AppTheme.accent, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
              child: Text(text,
                  style: const TextStyle(fontSize: 14, height: 1.4))),
        ],
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
