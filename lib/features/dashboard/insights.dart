import 'package:flutter/material.dart';

import '../../core/money.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/category.dart';
import '../../data/models/receipt.dart';
import 'analytics.dart';

class Insight {
  final String message;
  final IconData icon;
  final Color color;
  const Insight(this.message, this.icon, this.color);
}

/// Rule-based "AI Financial Coach" insights. This is the local MVP; it can be
/// upgraded to LLM-generated narratives later.
List<Insight> generateInsights(List<Receipt> receipts, String currency) {
  final a = SpendingAnalytics.compute(receipts);
  final insights = <Insight>[];

  if (receipts.isEmpty) {
    return [
      const Insight(
        'Scan your first receipt to unlock personalised money insights.',
        Icons.tips_and_updates_outlined,
        AppTheme.brand,
      ),
    ];
  }

  // Trend insight.
  final trend = a.trendPercent;
  if (trend != null && trend.abs() >= 5) {
    final up = trend > 0;
    insights.add(Insight(
      'Your spending is ${up ? 'up' : 'down'} ${trend.abs().toStringAsFixed(0)}% '
      'compared to last month.',
      up ? Icons.trending_up : Icons.trending_down,
      up ? const Color(0xFFEF4444) : AppTheme.accent,
    ));
  }

  // Dominant category insight.
  if (a.biggestCategory != null && a.monthlySpend > 0) {
    final share = a.biggestCategoryAmount / a.monthlySpend * 100;
    if (share >= 30) {
      insights.add(Insight(
        '${a.biggestCategory!.label} are consuming ${share.toStringAsFixed(0)}% '
        'of your spending this month (${Money(a.biggestCategoryAmount, currency).format()}).',
        a.biggestCategory!.icon,
        a.biggestCategory!.color,
      ));
    }
  }

  // Category-specific spend callout (fuel / eating out).
  final fuel = a.byCategory[ExpenseCategory.fuel] ?? 0;
  if (fuel > 0) {
    insights.add(Insight(
      'You spent ${Money(fuel, currency).format()} on fuel this month.',
      ExpenseCategory.fuel.icon,
      ExpenseCategory.fuel.color,
    ));
  }
  final fun = a.byCategory[ExpenseCategory.entertainment] ?? 0;
  if (fun > 0) {
    insights.add(Insight(
      'Eating out & entertainment cost you ${Money(fun, currency).format()}.',
      ExpenseCategory.entertainment.icon,
      ExpenseCategory.entertainment.color,
    ));
  }

  if (insights.isEmpty) {
    insights.add(Insight(
      'You\'ve logged ${a.receiptCount} receipts this month totalling '
      '${Money(a.monthlySpend, currency).format()}. Keep it up!',
      Icons.check_circle_outline,
      AppTheme.accent,
    ));
  }

  return insights.take(4).toList();
}
