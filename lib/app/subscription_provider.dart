import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/config/subscription_config.dart';
import '../core/services/subscription_service.dart';
import '../core/services/usage_service.dart';
import '../data/models/subscription_tier.dart';

// ── Singletons ────────────────────────────────────────────────────────────────

final subscriptionServiceProvider = Provider<SubscriptionService>((ref) {
  return SubscriptionService();
});

final _prefsProvider = FutureProvider<SharedPreferences>((ref) async {
  return SharedPreferences.getInstance();
});

final usageServiceProvider = Provider<UsageService?>((ref) {
  final prefsAsync = ref.watch(_prefsProvider);
  return prefsAsync.maybeWhen(
    data: (prefs) => UsageService(prefs),
    orElse: () => null,
  );
});

// ── Current subscription tier ─────────────────────────────────────────────────

/// Exposes the user's active [SubscriptionTier].
/// Invalidate this provider after a successful purchase or restore.
final subscriptionTierProvider =
    StateNotifierProvider<SubscriptionTierNotifier, SubscriptionTier>((ref) {
  final service = ref.watch(subscriptionServiceProvider);
  return SubscriptionTierNotifier(service);
});

class SubscriptionTierNotifier extends StateNotifier<SubscriptionTier> {
  final SubscriptionService _service;

  SubscriptionTierNotifier(this._service) : super(SubscriptionTier.free) {
    _load();
  }

  Future<void> _load() async {
    final tier = await _service.currentTier();
    if (mounted) state = tier;
  }

  Future<void> refresh() async {
    final tier = await _service.currentTier();
    if (mounted) state = tier;
  }

  /// Called after a successful external payment (Flutterwave / M-Pesa).
  void setTier(SubscriptionTier tier) {
    if (mounted) state = tier;
  }
}

// ── Convenience: capabilities for the current tier ───────────────────────────

final tierCapabilitiesProvider = Provider<TierCapabilities>((ref) {
  final tier = ref.watch(subscriptionTierProvider);
  return SubscriptionConfig.capsFor(tier);
});

// ── Usage stats ───────────────────────────────────────────────────────────────

final scansThisMonthProvider = Provider<int>((ref) {
  final usage = ref.watch(usageServiceProvider);
  return usage?.scansThisMonth ?? 0;
});

final canScanProvider = Provider<bool>((ref) {
  final caps = ref.watch(tierCapabilitiesProvider);
  final usage = ref.watch(usageServiceProvider);
  return usage?.canScan(caps.maxScansPerMonth) ?? true;
});
