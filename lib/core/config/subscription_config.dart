import '../../data/models/subscription_tier.dart';

class SubscriptionConfig {
  SubscriptionConfig._();

  // ── RevenueCat product IDs (Google Play) ─────────────────────────────────
  static const rcStarterMonthly = 'receiptiq_starter_monthly';
  static const rcProMonthly = 'receiptiq_pro_monthly';

  // ── RevenueCat entitlement IDs ────────────────────────────────────────────
  static const entitlementStarter = 'starter';
  static const entitlementPro = 'pro';

  // ── Tier capabilities ─────────────────────────────────────────────────────
  static const free = TierCapabilities(
    tier: SubscriptionTier.free,
    maxScansPerMonth: 5,
    maxBudgets: 1,
    historyDays: 30,
    aiMonthlyReview: false,
    fullAiInsights: false,
    csvExport: false,
  );

  static const starter = TierCapabilities(
    tier: SubscriptionTier.starter,
    maxScansPerMonth: 50,
    maxBudgets: 5,
    historyDays: 180,
    aiMonthlyReview: true,
    fullAiInsights: true,
    csvExport: false,
  );

  static const pro = TierCapabilities(
    tier: SubscriptionTier.pro,
    maxScansPerMonth: -1,
    maxBudgets: -1,
    historyDays: -1,
    aiMonthlyReview: true,
    fullAiInsights: true,
    csvExport: true,
  );

  static TierCapabilities capsFor(SubscriptionTier tier) {
    switch (tier) {
      case SubscriptionTier.free:
        return free;
      case SubscriptionTier.starter:
        return starter;
      case SubscriptionTier.pro:
        return pro;
    }
  }

  // ── Local African pricing: [Starter, Pro] ─────────────────────────────────
  static const Map<String, LocalPrice> localPricing = {
    'KE': LocalPrice('KES', 250, 1000),
    'NG': LocalPrice('NGN', 3000, 12000),
    'GH': LocalPrice('GHS', 30, 120),
    'TZ': LocalPrice('TZS', 5000, 20000),
    'UG': LocalPrice('UGX', 7500, 30000),
    'RW': LocalPrice('RWF', 2500, 10000),
    'ZM': LocalPrice('ZMW', 55, 220),
    'ZA': LocalPrice('ZAR', 40, 160),
  };

  static const LocalPrice defaultPricing = LocalPrice('USD', 2, 8);

  static LocalPrice priceFor(String? countryCode) {
    if (countryCode == null) return defaultPricing;
    return localPricing[countryCode.toUpperCase()] ?? defaultPricing;
  }
}

class LocalPrice {
  final String currency;
  final int starter;
  final int pro;
  const LocalPrice(this.currency, this.starter, this.pro);
}
