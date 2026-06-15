enum SubscriptionTier { free, starter, pro }

class TierCapabilities {
  final SubscriptionTier tier;
  final int maxScansPerMonth;
  final int historyDays;
  final bool aiMonthlyReview;
  final bool fullAiInsights;
  final bool csvExport;

  const TierCapabilities({
    required this.tier,
    required this.maxScansPerMonth,
    required this.historyDays,
    required this.aiMonthlyReview,
    required this.fullAiInsights,
    required this.csvExport,
  });

  bool get isUnlimitedScans => maxScansPerMonth < 0;
  bool get isUnlimitedHistory => historyDays < 0;

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
