import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/subscription_config.dart';
import '../core/services/usage_service.dart';
import '../data/models/subscription_tier.dart';

// ── Singletons ────────────────────────────────────────────────────────────────

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
/// Invalidate this provider after a successful Pesapal payment.
final subscriptionTierProvider =
    StateNotifierProvider<SubscriptionTierNotifier, SubscriptionTier>((ref) {
  return SubscriptionTierNotifier();
});

class SubscriptionTierNotifier extends StateNotifier<SubscriptionTier> {
  SubscriptionTierNotifier() : super(SubscriptionTier.free) {
    _load();
  }

  Future<void> _load() async {
    // Load tier from Supabase user_subscriptions table
    try {
      final client = Supabase.instance.client;
      final userId = client.auth.currentUser?.id;
      if (userId == null) return;

      final row = await client
          .from('user_subscriptions')
          .select('tier, expires_at')
          .eq('user_id', userId)
          .maybeSingle();

      if (row == null) return;

      final expiresAt = row['expires_at'] != null
          ? DateTime.tryParse(row['expires_at'] as String)
          : null;

      if (expiresAt != null && expiresAt.isBefore(DateTime.now())) {
        if (mounted) state = SubscriptionTier.free;
        return;
      }

      final tier = _parseTier(row['tier'] as String?);
      if (mounted) state = tier;
    } catch (_) {
      // On error, keep current state (free by default)
    }
  }

  Future<void> refresh() async {
    await _load();
  }

  /// Called after a successful Pesapal payment.
  void setTier(SubscriptionTier tier) {
    if (mounted) state = tier;
  }

  SubscriptionTier _parseTier(String? value) {
    switch (value) {
      case 'pro':
        return SubscriptionTier.pro;
      case 'starter':
        return SubscriptionTier.starter;
      default:
        return SubscriptionTier.free;
    }
  }
}

// ── Convenience: capabilities for the current tier ───────────────────────────

final tierCapabilitiesProvider = Provider<TierCapabilities>((ref) {
  final tier = ref.watch(subscriptionTierProvider);
  return SubscriptionConfig.capsFor(tier);
});

// ── Full subscription record from Supabase ────────────────────────────────────

/// Fetches the raw subscription row so the UI can show provider / auto_renew details.
final userSubscriptionRecordProvider =
    FutureProvider<Map<String, dynamic>?>((ref) async {
  // Re-run whenever the tier changes (purchase / cancellation)
  ref.watch(subscriptionTierProvider);
  final user = Supabase.instance.client.auth.currentUser;
  if (user == null || user.isAnonymous) return null;
  final response = await Supabase.instance.client
      .from('user_subscriptions')
      .select(
          'tier, payment_provider, auto_renew, billing_period, expires_at, pesapal_subscription_id')
      .eq('user_id', user.id)
      .maybeSingle();
  return response;
});

// ── Usage stats ───────────────────────────────────────────────────────────────

final scansThisMonthProvider = Provider<int>((ref) {
  final usage = ref.watch(usageServiceProvider);
  return usage?.scansThisMonth ?? 0;
});

final canScanProvider = Provider<bool>((ref) {
  final caps = ref.watch(tierCapabilitiesProvider);
  final usage = ref.watch(usageServiceProvider);
  if (usage == null) return false; // prefs not loaded yet — block silently
  User? user;
  try { user = Supabase.instance.client.auth.currentUser; } catch (_) {}
  if (user == null || user.isAnonymous) {
    return usage.canGuestScan(SubscriptionConfig.guestMaxScans);
  }
  return usage.canScan(caps.maxScansPerMonth);
});

/// How many lifetime guest scans have been used (anonymous users only).
final guestScansUsedProvider = Provider<int>((ref) {
  return ref.watch(usageServiceProvider)?.guestScansUsed ?? 0;
});
