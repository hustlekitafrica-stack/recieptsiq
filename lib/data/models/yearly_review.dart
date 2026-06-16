import '../../data/models/category.dart';

/// A structured yearly financial review, combining rule-based analytics and
/// (optionally) an AI-generated narrative.
class YearlyReview {
  final int year;
  final double totalSpend;
  final Map<int, double> monthlyTotals;
  final Map<Category, double> byCategory;
  final Map<String, double> topMerchants;
  final int bestMonth;
  final int worstMonth;
  final int receiptCount;
  final double? yearOverYearChange;
  final String headline;
  final String summary;
  final List<String> savingsOpportunities;

  const YearlyReview({
    required this.year,
    required this.totalSpend,
    required this.monthlyTotals,
    required this.byCategory,
    required this.topMerchants,
    required this.bestMonth,
    required this.worstMonth,
    required this.receiptCount,
    this.yearOverYearChange,
    required this.headline,
    required this.summary,
    required this.savingsOpportunities,
  });

  factory YearlyReview.fromJson(Map<String, dynamic> json) {
    final rawMonthly = json['monthly_totals'] as Map? ?? {};
    final monthlyTotals = <int, double>{
      for (final e in rawMonthly.entries)
        int.tryParse(e.key.toString()) ?? 0: (e.value as num).toDouble(),
    };

    final rawCat = json['by_category'] as Map? ?? {};
    final byCategory = <Category, double>{
      for (final e in rawCat.entries)
        Category.fromKey(e.key.toString()): (e.value as num).toDouble(),
    };

    final rawMerchants = json['top_merchants'] as Map? ?? {};
    final topMerchants = <String, double>{
      for (final e in rawMerchants.entries)
        e.key.toString(): (e.value as num).toDouble(),
    };

    return YearlyReview(
      year: (json['year'] as num?)?.toInt() ?? DateTime.now().year,
      totalSpend: (json['total_spend'] as num?)?.toDouble() ?? 0,
      monthlyTotals: monthlyTotals,
      byCategory: byCategory,
      topMerchants: topMerchants,
      bestMonth: (json['best_month'] as num?)?.toInt() ?? 1,
      worstMonth: (json['worst_month'] as num?)?.toInt() ?? 1,
      receiptCount: (json['receipt_count'] as num?)?.toInt() ?? 0,
      yearOverYearChange: (json['yoy_change'] as num?)?.toDouble(),
      headline: (json['headline'] ?? '').toString(),
      summary: (json['summary'] ?? '').toString(),
      savingsOpportunities: _list(json['savings_opportunities']),
    );
  }

  Map<String, dynamic> toJson() => {
        'year': year,
        'total_spend': totalSpend,
        'monthly_totals': {
          for (final e in monthlyTotals.entries) e.key.toString(): e.value,
        },
        'by_category': {
          for (final e in byCategory.entries) e.key.key: e.value,
        },
        'top_merchants': topMerchants,
        'best_month': bestMonth,
        'worst_month': worstMonth,
        'receipt_count': receiptCount,
        'yoy_change': yearOverYearChange,
        'headline': headline,
        'summary': summary,
        'savings_opportunities': savingsOpportunities,
      };

  static List<String> _list(dynamic v) {
    if (v is List) return v.map((e) => e.toString()).toList();
    return [];
  }
}
