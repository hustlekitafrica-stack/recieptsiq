import '../../data/models/category.dart';
import '../../data/models/receipt.dart';

/// Computed spending analytics for a set of receipts within a month.
///
/// MVP note: amounts are summed using their numeric value. Cross-currency
/// conversion is a future enhancement; seed/most data shares one currency.
class SpendingAnalytics {
  final double monthlySpend;
  final double lastMonthSpend;
  final ExpenseCategory? biggestCategory;
  final double biggestCategoryAmount;
  final String? topMerchant;
  final double averageDailySpend;
  final Map<ExpenseCategory, double> byCategory;
  final int receiptCount;

  const SpendingAnalytics({
    required this.monthlySpend,
    required this.lastMonthSpend,
    required this.biggestCategory,
    required this.biggestCategoryAmount,
    required this.topMerchant,
    required this.averageDailySpend,
    required this.byCategory,
    required this.receiptCount,
  });

  /// Month-over-month percentage change (positive = spending up).
  double? get trendPercent {
    if (lastMonthSpend <= 0) return null;
    return ((monthlySpend - lastMonthSpend) / lastMonthSpend) * 100;
  }

  factory SpendingAnalytics.compute(
    List<Receipt> receipts, {
    DateTime? now,
  }) {
    final ref = now ?? DateTime.now();
    final thisMonth =
        receipts.where((r) => _sameMonth(r.date, ref)).toList();
    final lastMonthRef = DateTime(ref.year, ref.month - 1, 1);
    final lastMonth =
        receipts.where((r) => _sameMonth(r.date, lastMonthRef)).toList();

    final byCategory = <ExpenseCategory, double>{};
    final byMerchant = <String, double>{};
    double total = 0;
    for (final r in thisMonth) {
      final amt = r.total.amount;
      total += amt;
      byCategory.update(r.category, (v) => v + amt, ifAbsent: () => amt);
      byMerchant.update(r.merchant, (v) => v + amt, ifAbsent: () => amt);
    }

    ExpenseCategory? biggestCat;
    double biggestAmt = 0;
    byCategory.forEach((k, v) {
      if (v > biggestAmt) {
        biggestAmt = v;
        biggestCat = k;
      }
    });

    String? topMerchant;
    double topMerchantAmt = 0;
    byMerchant.forEach((k, v) {
      if (v > topMerchantAmt) {
        topMerchantAmt = v;
        topMerchant = k;
      }
    });

    final daysElapsed = ref.day;
    final avgDaily = daysElapsed > 0 ? total / daysElapsed : 0;

    return SpendingAnalytics(
      monthlySpend: total,
      lastMonthSpend: lastMonth.fold(0, (s, r) => s + r.total.amount),
      biggestCategory: biggestCat,
      biggestCategoryAmount: biggestAmt,
      topMerchant: topMerchant,
      averageDailySpend: avgDaily.toDouble(),
      byCategory: byCategory,
      receiptCount: thisMonth.length,
    );
  }

  static bool _sameMonth(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month;
}

/// Computed analytics for a full calendar year.
class YearlyAnalytics {
  final int year;
  final double totalSpend;
  final double prevYearSpend;
  final Map<int, double> monthlyTotals;
  final Map<ExpenseCategory, double> byCategory;
  final Map<String, double> topMerchants;
  final int bestMonth;
  final int worstMonth;
  final int receiptCount;

  const YearlyAnalytics({
    required this.year,
    required this.totalSpend,
    required this.prevYearSpend,
    required this.monthlyTotals,
    required this.byCategory,
    required this.topMerchants,
    required this.bestMonth,
    required this.worstMonth,
    required this.receiptCount,
  });

  double? get yearOverYearChange {
    if (prevYearSpend <= 0) return null;
    return ((totalSpend - prevYearSpend) / prevYearSpend) * 100;
  }

  factory YearlyAnalytics.compute(List<Receipt> receipts, int year) {
    final thisYear = receipts.where((r) => r.date.year == year).toList();
    final prevYear = receipts.where((r) => r.date.year == year - 1).toList();

    final monthlyTotals = <int, double>{};
    final byCategory = <ExpenseCategory, double>{};
    final byMerchant = <String, double>{};
    double total = 0;

    for (final r in thisYear) {
      final amt = r.total.amount;
      total += amt;
      monthlyTotals.update(r.date.month, (v) => v + amt, ifAbsent: () => amt);
      byCategory.update(r.category, (v) => v + amt, ifAbsent: () => amt);
      byMerchant.update(r.merchant, (v) => v + amt, ifAbsent: () => amt);
    }

    int bestMonth = 1;
    int worstMonth = 1;
    double bestAmt = double.infinity;
    double worstAmt = 0;
    monthlyTotals.forEach((m, v) {
      if (v < bestAmt) { bestAmt = v; bestMonth = m; }
      if (v > worstAmt) { worstAmt = v; worstMonth = m; }
    });

    final sortedMerchants = byMerchant.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topMerchants = Map.fromEntries(sortedMerchants.take(5));

    return YearlyAnalytics(
      year: year,
      totalSpend: total,
      prevYearSpend: prevYear.fold(0, (s, r) => s + r.total.amount),
      monthlyTotals: monthlyTotals,
      byCategory: byCategory,
      topMerchants: topMerchants,
      bestMonth: monthlyTotals.isEmpty ? 1 : bestMonth,
      worstMonth: monthlyTotals.isEmpty ? 1 : worstMonth,
      receiptCount: thisYear.length,
    );
  }
}
