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
