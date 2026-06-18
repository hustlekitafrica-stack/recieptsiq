import 'package:purchases_flutter/purchases_flutter.dart';

import '../config/env.dart';
import '../config/subscription_config.dart';
import '../../data/models/subscription_tier.dart';

/// Wraps RevenueCat `purchases_flutter`.
///
/// When `REVENUECAT_GOOGLE_KEY` is absent (dev / offline mode) every call
/// gracefully returns [SubscriptionTier.pro] so all features remain accessible
/// during development.
class SubscriptionService {
  bool _configured = false;

  Future<void> configure({String? userId}) async {
    if (!Env.hasRevenueCat) return;
    await Purchases.setLogLevel(LogLevel.warn);
    final config = PurchasesConfiguration(Env.revenueCatGoogleKey);
    await Purchases.configure(config);
    if (userId != null) {
      await Purchases.logIn(userId);
    }
    _configured = true;
  }

  /// Returns the user's current active tier by inspecting RevenueCat
  /// entitlements. Falls back to [SubscriptionTier.free] on any error.
  Future<SubscriptionTier> currentTier() async {
    if (!Env.hasRevenueCat) return SubscriptionTier.free;
    if (!_configured) return SubscriptionTier.free;
    try {
      final info = await Purchases.getCustomerInfo();
      return _tierFromInfo(info);
    } catch (_) {
      return SubscriptionTier.free;
    }
  }

  /// Purchase a product by its Play Store product ID.
  /// Returns the resulting tier on success, throws on user cancellation or
  /// network error.
  Future<SubscriptionTier> purchase(String productId) async {
    final offerings = await Purchases.getOfferings();
    final pkg = _packageForProductId(offerings, productId);
    if (pkg == null) throw Exception('Product $productId not found');
    final info = await Purchases.purchasePackage(pkg);
    return _tierFromInfo(info);
  }

  /// Restores previous purchases (for users who reinstall).
  Future<SubscriptionTier> restore() async {
    if (!Env.hasRevenueCat) return SubscriptionTier.free;
    final info = await Purchases.restorePurchases();
    return _tierFromInfo(info);
  }

  // ── helpers ───────────────────────────────────────────────────────────────

  SubscriptionTier _tierFromInfo(CustomerInfo info) {
    final active = info.entitlements.active;
    if (active.containsKey(SubscriptionConfig.entitlementPro)) {
      return SubscriptionTier.pro;
    }
    if (active.containsKey(SubscriptionConfig.entitlementStarter)) {
      return SubscriptionTier.starter;
    }
    return SubscriptionTier.free;
  }

  Package? _packageForProductId(Offerings offerings, String productId) {
    for (final offering in offerings.all.values) {
      for (final pkg in offering.availablePackages) {
        if (pkg.storeProduct.identifier == productId) return pkg;
      }
    }
    return null;
  }
}
