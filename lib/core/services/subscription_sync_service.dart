import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/models/subscription_tier.dart';

/// Reads the canonical subscription record from Supabase `user_subscriptions`
/// and returns the active [SubscriptionTier].
///
/// This is called on app resume and after a mobile-money payment so the
/// Flutter app reflects the backend state (Flutterwave / Pesapal / M-Pesa
/// subscriptions are activated server-side via webhooks/callbacks).
class SubscriptionSyncService {
  final SupabaseClient _client;
  SubscriptionSyncService(this._client);

  /// Fetches the user's subscription tier from Supabase.
  /// Returns [SubscriptionTier.free] if no record exists or on any error.
  Future<SubscriptionTier> fetchTier() async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) return SubscriptionTier.free;

      final row = await _client
          .from('user_subscriptions')
          .select('tier, expires_at')
          .eq('user_id', userId)
          .maybeSingle();

      if (row == null) return SubscriptionTier.free;

      final expiresAt = row['expires_at'] != null
          ? DateTime.tryParse(row['expires_at'] as String)
          : null;

      if (expiresAt != null && expiresAt.isBefore(DateTime.now())) {
        return SubscriptionTier.free;
      }

      return _parseTier(row['tier'] as String?);
    } catch (_) {
      return SubscriptionTier.free;
    }
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
