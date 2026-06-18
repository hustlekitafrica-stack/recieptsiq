import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/models/receipt.dart';

enum HealthPillar { consistency, supplierControl, costTrend, budgetDiscipline }

class PillarScore {
  final HealthPillar pillar;
  final int score;
  final String label;
  final String description;
  final bool good;

  const PillarScore({
    required this.pillar,
    required this.score,
    required this.label,
    required this.description,
    required this.good,
  });

  IconData get icon {
    switch (pillar) {
      case HealthPillar.consistency:
        return Icons.show_chart;
      case HealthPillar.supplierControl:
        return Icons.store_outlined;
      case HealthPillar.costTrend:
        return Icons.trending_flat;
      case HealthPillar.budgetDiscipline:
        return Icons.savings_outlined;
    }
  }
}

class BusinessHealthScore {
  final int score;
  final List<PillarScore> pillars;

  const BusinessHealthScore({required this.score, required this.pillars});

  String get grade {
    if (score >= 80) return 'Excellent';
    if (score >= 65) return 'Good';
    if (score >= 50) return 'Fair';
    return 'Needs Attention';
  }

  Color get gradeColor {
    if (score >= 80) return const Color(0xFF22C55E);
    if (score >= 65) return const Color(0xFF84CC16);
    if (score >= 50) return const Color(0xFFF59E0B);
    return const Color(0xFFEF4444);
  }

  static BusinessHealthScore compute(
    List<Receipt> receipts, {
    double? monthlyBudget,
    DateTime? now,
  }) {
    final ref = now ?? DateTime.now();
    final p1 = _consistencyScore(receipts, ref);
    final p2 = _supplierControlScore(receipts, ref);
    final p3 = _costTrendScore(receipts, ref);
    final p4 = _budgetDisciplineScore(receipts, ref, monthlyBudget);
    final total = p1.score + p2.score + p3.score + p4.score;
    return BusinessHealthScore(score: total, pillars: [p1, p2, p3, p4]);
  }

  static double _stdDev(List<double> values) {
    if (values.length < 2) return 0;
    final mean = values.reduce((a, b) => a + b) / values.length;
    final variance =
        values.map((v) => math.pow(v - mean, 2)).reduce((a, b) => a + b) /
            values.length;
    return math.sqrt(variance);
  }

  static PillarScore _consistencyScore(List<Receipt> receipts, DateTime ref) {
    final monthly = <double>[];
    for (var i = 5; i >= 0; i--) {
      final m = DateTime(ref.year, ref.month - i, 1);
      final total = receipts
          .where((r) => r.date.year == m.year && r.date.month == m.month)
          .fold<double>(0, (s, r) => s + r.total.amount);
      monthly.add(total);
    }
    final nonZero = monthly.where((v) => v > 0).toList();
    if (nonZero.length < 2) {
      return const PillarScore(
        pillar: HealthPillar.consistency,
        score: 20,
        label: 'Spending consistency',
        description: 'Not enough data yet',
        good: true,
      );
    }
    final mean = nonZero.reduce((a, b) => a + b) / nonZero.length;
    final cv = mean > 0 ? _stdDev(nonZero) / mean : 1.0;
    int pts;
    String desc;
    bool good;
    if (cv < 0.2) {
      pts = 25; desc = 'Very consistent spending'; good = true;
    } else if (cv < 0.4) {
      pts = 18; desc = 'Mostly consistent'; good = true;
    } else if (cv < 0.6) {
      pts = 12; desc = 'Some monthly variation'; good = false;
    } else {
      pts = 5; desc = 'High spending volatility'; good = false;
    }
    return PillarScore(
      pillar: HealthPillar.consistency,
      score: pts,
      label: 'Spending consistency',
      description: desc,
      good: good,
    );
  }

  static PillarScore _supplierControlScore(
      List<Receipt> receipts, DateTime ref) {
    final recent = <Receipt>[];
    for (var i = 0; i < 3; i++) {
      final m = DateTime(ref.year, ref.month - i, 1);
      recent.addAll(receipts
          .where((r) => r.date.year == m.year && r.date.month == m.month));
    }
    if (recent.isEmpty) {
      return const PillarScore(
        pillar: HealthPillar.supplierControl,
        score: 20,
        label: 'Supplier control',
        description: 'Not enough data yet',
        good: true,
      );
    }
    final byMerchant = <String, double>{};
    final total = recent.fold<double>(0, (s, r) => s + r.total.amount);
    for (final r in recent) {
      byMerchant.update(r.merchant, (v) => v + r.total.amount,
          ifAbsent: () => r.total.amount);
    }
    double hhi = 0;
    if (total > 0) {
      for (final v in byMerchant.values) {
        final share = v / total;
        hhi += share * share;
      }
    }
    int pts;
    String desc;
    bool good;
    if (hhi < 0.15) {
      pts = 25; desc = 'Well-diversified suppliers'; good = true;
    } else if (hhi < 0.25) {
      pts = 20; desc = 'Good supplier diversity'; good = true;
    } else if (hhi < 0.40) {
      pts = 12; desc = 'Moderate supplier concentration'; good = false;
    } else {
      pts = 5; desc = 'High supplier concentration'; good = false;
    }
    return PillarScore(
      pillar: HealthPillar.supplierControl,
      score: pts,
      label: 'Supplier control',
      description: desc,
      good: good,
    );
  }

  static PillarScore _costTrendScore(List<Receipt> receipts, DateTime ref) {
    final lm = DateTime(ref.year, ref.month - 1, 1);
    final thisMonth = receipts
        .where((r) => r.date.year == ref.year && r.date.month == ref.month)
        .fold<double>(0, (s, r) => s + r.total.amount);
    final lastMonth = receipts
        .where((r) => r.date.year == lm.year && r.date.month == lm.month)
        .fold<double>(0, (s, r) => s + r.total.amount);
    if (lastMonth <= 0 || thisMonth <= 0) {
      return const PillarScore(
        pillar: HealthPillar.costTrend,
        score: 20,
        label: 'Cost trends',
        description: 'Insufficient history',
        good: true,
      );
    }
    final change = ((thisMonth - lastMonth) / lastMonth) * 100;
    int pts;
    String desc;
    bool good;
    if (change <= 0) {
      pts = 25; desc = 'Costs trending down'; good = true;
    } else if (change < 5) {
      pts = 20; desc = 'Costs roughly flat'; good = true;
    } else if (change < 15) {
      pts = 12;
      desc = 'Costs up ${change.toStringAsFixed(0)}% this month';
      good = false;
    } else {
      pts = 5;
      desc = 'Costs up ${change.toStringAsFixed(0)}% — review spending';
      good = false;
    }
    return PillarScore(
      pillar: HealthPillar.costTrend,
      score: pts,
      label: 'Cost trends',
      description: desc,
      good: good,
    );
  }

  static PillarScore _budgetDisciplineScore(
      List<Receipt> receipts, DateTime ref, double? budget) {
    if (budget == null || budget <= 0) {
      return const PillarScore(
        pillar: HealthPillar.budgetDiscipline,
        score: 20,
        label: 'Budget discipline',
        description: 'Set a budget to track',
        good: true,
      );
    }
    final spend = receipts
        .where((r) => r.date.year == ref.year && r.date.month == ref.month)
        .fold<double>(0, (s, r) => s + r.total.amount);
    final pct = spend / budget * 100;
    int pts;
    String desc;
    bool good;
    if (pct <= 75) {
      pts = 25; desc = 'Within budget'; good = true;
    } else if (pct <= 90) {
      pts = 18;
      desc = '${pct.toStringAsFixed(0)}% of budget used';
      good = true;
    } else if (pct <= 100) {
      pts = 10; desc = 'Near budget limit'; good = false;
    } else {
      pts = 5;
      desc = 'Over budget by ${(pct - 100).toStringAsFixed(0)}%';
      good = false;
    }
    return PillarScore(
      pillar: HealthPillar.budgetDiscipline,
      score: pts,
      label: 'Budget discipline',
      description: desc,
      good: good,
    );
  }
}
