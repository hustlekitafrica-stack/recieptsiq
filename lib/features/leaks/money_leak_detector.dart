import 'package:flutter/material.dart';

import '../../core/money.dart';
import '../../data/models/receipt.dart';

enum LeakType { microSpend, frequencyExcess, supplierPriceDrift, categoryConcentration }

class MoneyLeak {
  final String title;
  final String detail;
  final String actionHint;
  final double savingAmount;
  final LeakType type;
  final IconData icon;
  final Color color;

  const MoneyLeak({
    required this.title,
    required this.detail,
    required this.actionHint,
    required this.savingAmount,
    required this.type,
    required this.icon,
    required this.color,
  });
}

class MoneyLeakDetector {
  static List<MoneyLeak> detect(
    List<Receipt> receipts,
    String currency, {
    DateTime? now,
  }) {
    final ref = now ?? DateTime.now();
    final thisMonth = receipts
        .where((r) => r.date.year == ref.year && r.date.month == ref.month)
        .toList();
    final lm = DateTime(ref.year, ref.month - 1, 1);
    final lastMonth = receipts
        .where((r) => r.date.year == lm.year && r.date.month == lm.month)
        .toList();

    if (thisMonth.isEmpty) return [];

    final leaks = <MoneyLeak>[];

    // 1. Micro-spend accumulation
    final avgMonthly = _avgMonthly(receipts, ref);
    final microThreshold = (avgMonthly * 0.01).clamp(200.0, 2000.0);
    final microSpends =
        thisMonth.where((r) => r.total.amount < microThreshold).toList();
    if (microSpends.length >= 5) {
      final microTotal =
          microSpends.fold<double>(0, (s, r) => s + r.total.amount);
      leaks.add(MoneyLeak(
        title: 'Small purchase accumulation',
        detail:
            '${microSpends.length} purchases under ${Money(microThreshold, currency).format()} '
            'totalling ${Money(microTotal, currency).format()} this month.',
        actionHint:
            'Consolidate these into fewer, larger orders to reduce overhead.',
        savingAmount: microTotal * 0.2,
        type: LeakType.microSpend,
        icon: Icons.shopping_cart_outlined,
        color: const Color(0xFFF59E0B),
      ));
    }

    // 2. Frequency excess — same merchant ≥ 4 times/month
    final merchantReceipts = <String, List<Receipt>>{};
    for (final r in thisMonth) {
      merchantReceipts.update(r.merchant, (l) => [...l, r],
          ifAbsent: () => [r]);
    }
    for (final entry in merchantReceipts.entries) {
      if (entry.value.length >= 4) {
        final totalSpent =
            entry.value.fold<double>(0, (s, r) => s + r.total.amount);
        final potentialSaving = totalSpent * 0.12;
        leaks.add(MoneyLeak(
          title: 'Frequent purchases at ${entry.key}',
          detail:
              '${entry.value.length} purchases this month totalling ${Money(totalSpent, currency).format()}. '
              'Buying in bulk could save approximately ${Money(potentialSaving, currency).format()}.',
          actionHint: 'Negotiate a bulk or monthly order rate.',
          savingAmount: potentialSaving,
          type: LeakType.frequencyExcess,
          icon: Icons.repeat_outlined,
          color: const Color(0xFF3B82F6),
        ));
      }
    }

    // 3. Supplier price drift — avg receipt total up ≥ 10% MoM
    final lastByMerchant = <String, List<double>>{};
    for (final r in lastMonth) {
      lastByMerchant.update(r.merchant, (l) => [...l, r.total.amount],
          ifAbsent: () => [r.total.amount]);
    }
    for (final entry in merchantReceipts.entries) {
      final lastList = lastByMerchant[entry.key];
      if (lastList == null || lastList.isEmpty) continue;
      final thisAvg =
          entry.value.fold<double>(0, (s, r) => s + r.total.amount) /
              entry.value.length;
      final lastAvg = lastList.reduce((a, b) => a + b) / lastList.length;
      if (lastAvg <= 0) continue;
      final changePct = ((thisAvg - lastAvg) / lastAvg) * 100;
      if (changePct >= 10) {
        final excess = (thisAvg - lastAvg) * entry.value.length;
        leaks.add(MoneyLeak(
          title: 'Price increase at ${entry.key}',
          detail:
              'Average receipt is up ${changePct.toStringAsFixed(0)}% vs last month. '
              'You\'re paying approximately ${Money(excess, currency).format()} more.',
          actionHint:
              'Renegotiate prices or compare with alternative suppliers.',
          savingAmount: excess,
          type: LeakType.supplierPriceDrift,
          icon: Icons.price_change_outlined,
          color: const Color(0xFFEF4444),
        ));
      }
    }

    // 4. Category concentration — one category > 60% of spend
    if (thisMonth.isNotEmpty) {
      final totalThisMonth =
          thisMonth.fold<double>(0, (s, r) => s + r.total.amount);
      final byCategory = <String, double>{};
      for (final r in thisMonth) {
        byCategory.update(r.category.label, (v) => v + r.total.amount,
            ifAbsent: () => r.total.amount);
      }
      for (final entry in byCategory.entries) {
        final share = totalThisMonth > 0
            ? entry.value / totalThisMonth * 100
            : 0.0;
        if (share > 60) {
          leaks.add(MoneyLeak(
            title: '${entry.key} dominates your spending',
            detail:
                '${share.toStringAsFixed(0)}% of this month\'s expenses are on ${entry.key} '
                '(${Money(entry.value, currency).format()}).',
            actionHint:
                'Review whether all ${entry.key} purchases are essential.',
            savingAmount: entry.value * 0.1,
            type: LeakType.categoryConcentration,
            icon: Icons.pie_chart_outline,
            color: const Color(0xFF8B5CF6),
          ));
        }
      }
    }

    leaks.sort((a, b) => b.savingAmount.compareTo(a.savingAmount));
    return leaks;
  }

  static double _avgMonthly(List<Receipt> receipts, DateTime ref) {
    double sum = 0;
    int count = 0;
    for (var i = 1; i <= 6; i++) {
      final m = DateTime(ref.year, ref.month - i, 1);
      final total = receipts
          .where((r) => r.date.year == m.year && r.date.month == m.month)
          .fold<double>(0, (s, r) => s + r.total.amount);
      if (total > 0) { sum += total; count++; }
    }
    return count > 0 ? sum / count : 5000.0;
  }
}
