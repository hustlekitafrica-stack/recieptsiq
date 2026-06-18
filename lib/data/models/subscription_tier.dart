enum SubscriptionTier { free, starter, pro }

enum BillingPeriod { monthly, yearly }

class PaymentArgs {
  final SubscriptionTier tier;
  final BillingPeriod billingPeriod;
  const PaymentArgs({required this.tier, required this.billingPeriod});
}

class TierCapabilities {
  final SubscriptionTier tier;
  final int maxScansPerMonth;
  final int historyDays;
  final bool aiMonthlyReview;
  final bool fullAiInsights;
  final bool csvExport;
  final bool pdfExport;
  final bool fullHealthScore;
  final int maxLeaksShown;
  final bool supplierIntelligence;
  final bool postScanInsight;
  final int aiChatQueriesPerMonth;
  final bool aiYearlyReview;

  const TierCapabilities({
    required this.tier,
    required this.maxScansPerMonth,
    required this.historyDays,
    required this.aiMonthlyReview,
    required this.fullAiInsights,
    required this.csvExport,
    required this.pdfExport,
    required this.fullHealthScore,
    required this.maxLeaksShown,
    required this.supplierIntelligence,
    required this.postScanInsight,
    required this.aiChatQueriesPerMonth,
    required this.aiYearlyReview,
  });

  bool get isUnlimitedScans => maxScansPerMonth < 0;
  bool get isUnlimitedHistory => historyDays < 0;
  bool get isUnlimitedLeaks => maxLeaksShown < 0;
  bool get isUnlimitedAiChat => aiChatQueriesPerMonth < 0;

  String get displayName {
    switch (tier) {
      case SubscriptionTier.free:
        return 'Free';
      case SubscriptionTier.starter:
        return 'Starter';
      case SubscriptionTier.pro:
        return 'Pro';
    }
  }
}
