import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/providers.dart';
import '../../core/money.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/category.dart';
import '../../data/models/receipt.dart';
import '../../features/dashboard/analytics.dart';

class AnalyticsScreen extends ConsumerWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final receiptsAsync = ref.watch(receiptsProvider);
    final currency = ref.watch(displayCurrencyProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Analytics')),
      body: receiptsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (receipts) {
          if (receipts.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.bar_chart_outlined,
                        size: 56, color: Color(0xFFCBD5E1)),
                    SizedBox(height: 12),
                    Text('No data yet.',
                        style: TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 16)),
                    SizedBox(height: 6),
                    Text('Scan some receipts to see your analytics.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Color(0xFF94A3B8))),
                  ],
                ),
              ),
            );
          }

          final now = DateTime.now();
          final allTime = _allTimeStats(receipts, currency);
          final monthlyTotals = _last12MonthTotals(receipts, now);
          final byCategory = _categoryTotals(receipts);
          final topMerchants = _topMerchants(receipts);

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
            children: [
              // ── Summary card ────────────────────────────────────────────
              _SummaryCard(stats: allTime, currency: currency),
              const SizedBox(height: 20),

              // ── Monthly trend ───────────────────────────────────────────
              const _SectionTitle('Monthly trend'),
              const SizedBox(height: 10),
              _MonthlyTrendChart(
                  monthlyTotals: monthlyTotals, currency: currency),
              const SizedBox(height: 20),

              // ── Spending by category ────────────────────────────────────
              const _SectionTitle('Spending by category'),
              const SizedBox(height: 10),
              ...byCategory.entries.map((e) => _CategoryRow(
                    category: e.key,
                    amount: e.value,
                    total: allTime.totalSpend,
                    currency: currency,
                    receipts: receipts,
                  )),
              const SizedBox(height: 12),

              // ── Top merchants ───────────────────────────────────────────
              const _SectionTitle('Top merchants'),
              const SizedBox(height: 10),
              _TopMerchantsCard(
                  merchants: topMerchants, currency: currency),
            ],
          );
        },
      ),
    );
  }

  _AllTimeStats _allTimeStats(List<Receipt> receipts, String currency) {
    final total =
        receipts.fold<double>(0, (s, r) => s + r.total.amount);
    final months = receipts.map((r) => '${r.date.year}-${r.date.month}').toSet();
    final avgMonthly = months.isEmpty ? 0.0 : total / months.length;
    return _AllTimeStats(
        totalSpend: total,
        receiptCount: receipts.length,
        avgMonthly: avgMonthly);
  }

  List<_MonthTotal> _last12MonthTotals(
      List<Receipt> receipts, DateTime now) {
    final result = <_MonthTotal>[];
    for (var i = 11; i >= 0; i--) {
      final m = DateTime(now.year, now.month - i, 1);
      final total = receipts
          .where((r) => r.date.year == m.year && r.date.month == m.month)
          .fold<double>(0, (s, r) => s + r.total.amount);
      result.add(_MonthTotal(month: m, total: total));
    }
    return result;
  }

  Map<Category, double> _categoryTotals(List<Receipt> receipts) {
    final map = <Category, double>{};
    for (final r in receipts) {
      final categorisedItems = r.items.where((it) => it.category != null).toList();
      if (categorisedItems.isNotEmpty) {
        for (final it in r.items) {
          final cat = it.category ?? r.category;
          map.update(cat, (v) => v + it.amount, ifAbsent: () => it.amount);
        }
      } else {
        map.update(r.category, (v) => v + r.total.amount,
            ifAbsent: () => r.total.amount);
      }
    }
    final sorted = map.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Map.fromEntries(sorted);
  }

  List<_MerchantStat> _topMerchants(List<Receipt> receipts) {
    final map = <String, _MerchantStat>{};
    for (final r in receipts) {
      map.putIfAbsent(r.merchant,
          () => _MerchantStat(name: r.merchant, total: 0, count: 0));
      map[r.merchant]!.total += r.total.amount;
      map[r.merchant]!.count++;
    }
    final list = map.values.toList()
      ..sort((a, b) => b.total.compareTo(a.total));
    return list.take(10).toList();
  }
}

// ── Data holders ─────────────────────────────────────────────────────────────

class _AllTimeStats {
  final double totalSpend;
  final int receiptCount;
  final double avgMonthly;
  _AllTimeStats(
      {required this.totalSpend,
      required this.receiptCount,
      required this.avgMonthly});
}

class _MonthTotal {
  final DateTime month;
  final double total;
  _MonthTotal({required this.month, required this.total});
}

class _MerchantStat {
  final String name;
  double total;
  int count;
  _MerchantStat({required this.name, required this.total, required this.count});
  double get avg => count > 0 ? total / count : 0;
}

// ── Summary Card ──────────────────────────────────────────────────────────────

class _SummaryCard extends StatelessWidget {
  final _AllTimeStats stats;
  final String currency;
  const _SummaryCard({required this.stats, required this.currency});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppTheme.brand, AppTheme.brandDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Expanded(
            child: _HeroStat(
              label: 'Total spent',
              value: Money(stats.totalSpend, currency).format(),
            ),
          ),
          Container(width: 1, height: 48, color: Colors.white24),
          Expanded(
            child: _HeroStat(
              label: 'Avg / month',
              value: Money(stats.avgMonthly, currency).format(),
            ),
          ),
          Container(width: 1, height: 48, color: Colors.white24),
          Expanded(
            child: _HeroStat(
              label: 'Receipts',
              value: stats.receiptCount.toString(),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  final String label, value;
  const _HeroStat({required this.label, required this.value});
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value,
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 16)),
        const SizedBox(height: 2),
        Text(label,
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Colors.white70, fontSize: 11)),
      ],
    );
  }
}

// ── Monthly Trend Chart ───────────────────────────────────────────────────────

class _MonthlyTrendChart extends StatelessWidget {
  final List<_MonthTotal> monthlyTotals;
  final String currency;
  const _MonthlyTrendChart(
      {required this.monthlyTotals, required this.currency});

  @override
  Widget build(BuildContext context) {
    final maxVal = monthlyTotals.fold<double>(
        0, (m, e) => math.max(m, e.total));

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          children: monthlyTotals.map((mt) {
            final pct = maxVal > 0 ? mt.total / maxVal : 0.0;
            final label = DateFormat('MMM yy').format(mt.month);
            final isNow = mt.month.year == DateTime.now().year &&
                mt.month.month == DateTime.now().month;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 46,
                    child: Text(
                      label,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: isNow
                              ? FontWeight.w700
                              : FontWeight.w400,
                          color: isNow
                              ? AppTheme.brand
                              : const Color(0xFF64748B)),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(5),
                      child: LinearProgressIndicator(
                        value: pct,
                        minHeight: 18,
                        backgroundColor: const Color(0xFFEFF1F5),
                        valueColor: AlwaysStoppedAnimation(
                          isNow
                              ? AppTheme.brand
                              : AppTheme.brand.withValues(alpha: 0.55),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 70,
                    child: Text(
                      mt.total > 0
                          ? Money(mt.total, currency).format()
                          : '—',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: isNow
                              ? FontWeight.w700
                              : FontWeight.w400,
                          color: isNow
                              ? AppTheme.brand
                              : const Color(0xFF475569)),
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

// ── Category Row ──────────────────────────────────────────────────────────────

class _CategoryRow extends StatelessWidget {
  final Category category;
  final double amount;
  final double total;
  final String currency;
  final List<Receipt> receipts;
  const _CategoryRow({
    required this.category,
    required this.amount,
    required this.total,
    required this.currency,
    required this.receipts,
  });

  @override
  Widget build(BuildContext context) {
    final pct = total > 0 ? amount / total : 0.0;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openCategoryDetail(context),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color:
                          category.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child:
                        Icon(category.icon, color: category.color, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(category.label,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 14)),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(Money(amount, currency).format(),
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 14)),
                      Text('${(pct * 100).toStringAsFixed(1)}%',
                          style: const TextStyle(
                              color: Color(0xFF94A3B8), fontSize: 11)),
                    ],
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right,
                      size: 16, color: Color(0xFFCBD5E1)),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: pct,
                  minHeight: 6,
                  backgroundColor: const Color(0xFFEFF1F5),
                  valueColor: AlwaysStoppedAnimation(category.color),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openCategoryDetail(BuildContext context) {
    final catReceipts = receipts
        .where((r) => r.category == category)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CategoryDetailSheet(
        category: category,
        receipts: catReceipts,
        totalSpend: amount,
        currency: currency,
      ),
    );
  }
}

// ── Category Detail Sheet ─────────────────────────────────────────────────────

class _CategoryDetailSheet extends StatelessWidget {
  final Category category;
  final List<Receipt> receipts;
  final double totalSpend;
  final String currency;
  const _CategoryDetailSheet({
    required this.category,
    required this.receipts,
    required this.totalSpend,
    required this.currency,
  });

  Map<String, double> _monthBreakdown() {
    final map = <String, double>{};
    final fmt = DateFormat('MMM yyyy');
    for (final r in receipts) {
      final k = fmt.format(r.date);
      map.update(k, (v) => v + r.total.amount,
          ifAbsent: () => r.total.amount);
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final months = _monthBreakdown();
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFCBD5E1),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: category.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(category.icon,
                        color: category.color, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(category.label,
                            style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 17)),
                        Text(
                          '${receipts.length} receipt${receipts.length == 1 ? '' : 's'} · ${Money(totalSpend, currency).format()} total',
                          style: const TextStyle(
                              color: Color(0xFF64748B), fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (months.isNotEmpty) ...[
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('By month',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: Colors.grey[600])),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 36,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: months.entries.map((e) {
                    return Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: category.color.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${e.key}  ${Money(e.value, currency).format()}',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: category.color),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
            const SizedBox(height: 12),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                itemCount: receipts.length,
                itemBuilder: (ctx, i) {
                  final r = receipts[i];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      onTap: () {
                        Navigator.pop(ctx);
                        context.push('/receipt/${r.id}');
                      },
                      title: Text(r.merchant,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600)),
                      subtitle: Text(
                          DateFormat('d MMM yyyy').format(r.date)),
                      trailing: Text(r.total.format(),
                          style: const TextStyle(
                              fontWeight: FontWeight.w700)),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Top Merchants Card ────────────────────────────────────────────────────────

class _TopMerchantsCard extends StatelessWidget {
  final List<_MerchantStat> merchants;
  final String currency;
  const _TopMerchantsCard(
      {required this.merchants, required this.currency});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: merchants.asMap().entries.map((entry) {
            final i = entry.key;
            final m = entry.value;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AppTheme.brand.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Text(
                        m.name.isNotEmpty
                            ? m.name[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                            color: AppTheme.brand,
                            fontWeight: FontWeight.w800,
                            fontSize: 14),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(m.name,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13)),
                        Text(
                          '${m.count} visit${m.count == 1 ? '' : 's'} · avg ${Money(m.avg, currency).format()}',
                          style: const TextStyle(
                              color: Color(0xFF94A3B8), fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  Text(Money(m.total, currency).format(),
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 13)),
                  if (i == 0) ...[
                    const SizedBox(width: 6),
                    const Icon(Icons.star_rounded,
                        color: Color(0xFFF59E0B), size: 16),
                  ],
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

// ── Section title ─────────────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);
  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
      );
}
