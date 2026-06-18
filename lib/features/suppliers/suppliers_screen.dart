import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/providers.dart';
import '../../core/money.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/receipt.dart';

class _SupplierStat {
  final String name;
  final double totalSpent;
  final int visitCount;
  final double avgPerVisit;
  final double? priceChangePct;
  final String frequencyLabel;
  final String topCategory;
  final DateTime lastVisit;

  const _SupplierStat({
    required this.name,
    required this.totalSpent,
    required this.visitCount,
    required this.avgPerVisit,
    required this.priceChangePct,
    required this.frequencyLabel,
    required this.topCategory,
    required this.lastVisit,
  });
}

List<_SupplierStat> _buildStats(List<Receipt> receipts, DateTime now) {
  final byMerchant = <String, List<Receipt>>{};
  for (final r in receipts) {
    byMerchant.update(r.merchant, (l) => [...l, r], ifAbsent: () => [r]);
  }

  final lm = DateTime(now.year, now.month - 1, 1);

  final stats = byMerchant.entries.map((entry) {
    final all = entry.value..sort((a, b) => b.date.compareTo(a.date));
    final total = all.fold<double>(0, (s, r) => s + r.total.amount);
    final avg = all.isNotEmpty ? total / all.length : 0.0;

    final thisMonthList = all
        .where((r) => r.date.year == now.year && r.date.month == now.month)
        .toList();
    final lastMonthList = all
        .where((r) => r.date.year == lm.year && r.date.month == lm.month)
        .toList();

    double? changePct;
    if (thisMonthList.isNotEmpty && lastMonthList.isNotEmpty) {
      final thisAvg =
          thisMonthList.fold<double>(0, (s, r) => s + r.total.amount) /
              thisMonthList.length;
      final lastAvg =
          lastMonthList.fold<double>(0, (s, r) => s + r.total.amount) /
              lastMonthList.length;
      if (lastAvg > 0) changePct = ((thisAvg - lastAvg) / lastAvg) * 100;
    }

    final catFreq = <String, int>{};
    for (final r in all) {
      catFreq.update(r.category.label, (v) => v + 1, ifAbsent: () => 1);
    }
    final topCat =
        catFreq.entries.reduce((a, b) => a.value >= b.value ? a : b).key;

    String freqLabel;
    if (all.length >= 4) {
      final span = all.first.date.difference(all.last.date).inDays;
      final avgDaysBetween = span > 0 ? span / (all.length - 1) : 0;
      if (avgDaysBetween <= 8) {
        freqLabel = 'Weekly';
      } else if (avgDaysBetween <= 18) {
        freqLabel = 'Bi-weekly';
      } else if (avgDaysBetween <= 35) {
        freqLabel = 'Monthly';
      } else {
        freqLabel = 'Occasional';
      }
    } else {
      freqLabel = 'Occasional';
    }

    return _SupplierStat(
      name: entry.key,
      totalSpent: total,
      visitCount: all.length,
      avgPerVisit: avg,
      priceChangePct: changePct,
      frequencyLabel: freqLabel,
      topCategory: topCat,
      lastVisit: all.first.date,
    );
  }).toList();

  stats.sort((a, b) => b.totalSpent.compareTo(a.totalSpent));
  return stats;
}

class SuppliersScreen extends ConsumerWidget {
  const SuppliersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final receiptsAsync = ref.watch(receiptsProvider);
    final currency = ref.watch(displayCurrencyProvider);
    final now = DateTime.now();

    return Scaffold(
      appBar: AppBar(title: const Text('Supplier Intelligence')),
      body: receiptsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (receipts) {
          if (receipts.isEmpty) {
            return const _EmptyState();
          }
          final stats = _buildStats(receipts, now);
          final totalAllTime =
              receipts.fold<double>(0, (s, r) => s + r.total.amount);

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
            children: [
              _SummaryCard(
                  supplierCount: stats.length,
                  totalSpent: totalAllTime,
                  currency: currency),
              const SizedBox(height: 16),
              const _SectionLabel('All suppliers'),
              const SizedBox(height: 8),
              ...stats.map((s) => _SupplierCard(
                    stat: s,
                    currency: currency,
                    receipts: receipts
                        .where((r) => r.merchant == s.name)
                        .toList(),
                  )),
            ],
          );
        },
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final int supplierCount;
  final double totalSpent;
  final String currency;
  const _SummaryCard({
    required this.supplierCount,
    required this.totalSpent,
    required this.currency,
  });

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
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Expanded(
            child: _Stat(
              label: 'Suppliers tracked',
              value: supplierCount.toString(),
            ),
          ),
          Container(width: 1, height: 40, color: Colors.white24),
          Expanded(
            child: _Stat(
              label: 'Total spent',
              value: Money(totalSpent, currency).format(),
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label, value;
  const _Stat({required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Column(
        children: [
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 18)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ],
      );
}

class _SupplierCard extends StatelessWidget {
  final _SupplierStat stat;
  final String currency;
  final List<Receipt> receipts;
  const _SupplierCard({
    required this.stat,
    required this.currency,
    required this.receipts,
  });

  @override
  Widget build(BuildContext context) {
    final hasChange = stat.priceChangePct != null;
    final changeUp = (stat.priceChangePct ?? 0) > 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _openDetail(context),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppTheme.brand.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text(
                        stat.name.isNotEmpty
                            ? stat.name[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                            color: AppTheme.brand,
                            fontWeight: FontWeight.w800,
                            fontSize: 16),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(stat.name,
                            style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15)),
                        Text(
                          '${stat.topCategory} · ${stat.frequencyLabel}',
                          style: const TextStyle(
                              color: Color(0xFF94A3B8),
                              fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(Money(stat.totalSpent, currency).format(),
                          style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15)),
                      Text(
                        '${stat.visitCount} purchase${stat.visitCount == 1 ? '' : 's'}',
                        style: const TextStyle(
                            color: Color(0xFF94A3B8), fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _InfoChip(
                    label:
                        'Avg ${Money(stat.avgPerVisit, currency).format()} / visit',
                    icon: Icons.receipt_outlined,
                    color: const Color(0xFF64748B),
                  ),
                  const SizedBox(width: 8),
                  if (hasChange)
                    _InfoChip(
                      label:
                          'Price ${changeUp ? '↑' : '↓'} ${stat.priceChangePct!.abs().toStringAsFixed(0)}% MoM',
                      icon: changeUp
                          ? Icons.trending_up
                          : Icons.trending_down,
                      color: changeUp
                          ? const Color(0xFFEF4444)
                          : const Color(0xFF22C55E),
                    ),
                  const SizedBox(width: 8),
                  _InfoChip(
                    label:
                        'Last: ${DateFormat('d MMM').format(stat.lastVisit)}',
                    icon: Icons.calendar_today_outlined,
                    color: const Color(0xFF64748B),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openDetail(BuildContext context) {
    final sorted = [...receipts]..sort((a, b) => b.date.compareTo(a.date));
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SupplierDetailSheet(
        stat: stat,
        receipts: sorted,
        currency: currency,
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  const _InfoChip(
      {required this.label, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 11, color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _SupplierDetailSheet extends StatelessWidget {
  final _SupplierStat stat;
  final List<Receipt> receipts;
  final String currency;
  const _SupplierDetailSheet({
    required this.stat,
    required this.receipts,
    required this.currency,
  });

  @override
  Widget build(BuildContext context) {
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
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppTheme.brand.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text(
                        stat.name.isNotEmpty
                            ? stat.name[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                            color: AppTheme.brand,
                            fontWeight: FontWeight.w800,
                            fontSize: 18),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(stat.name,
                            style: const TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 17)),
                        Text(
                          '${stat.visitCount} purchases · ${Money(stat.totalSpent, currency).format()} total',
                          style: const TextStyle(
                              color: Color(0xFF64748B), fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
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
                        final router = GoRouter.of(context);
                        Navigator.of(context, rootNavigator: true).pop();
                        router.push('/receipt/${r.id}');
                      },
                      title: Text(DateFormat('d MMM yyyy').format(r.date),
                          style:
                              const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(r.category.label),
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

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700));
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.store_outlined, size: 56, color: Color(0xFFCBD5E1)),
            SizedBox(height: 12),
            Text('No suppliers yet',
                style:
                    TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
            SizedBox(height: 6),
            Text('Scan receipts to build your supplier intelligence.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF94A3B8))),
          ],
        ),
      ),
    );
  }
}
