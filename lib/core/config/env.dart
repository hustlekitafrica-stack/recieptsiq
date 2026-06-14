import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Centralised access to runtime configuration loaded from the `.env` asset.
///
/// Keys are intentionally NOT hardcoded in source. For production, OCR/LLM
/// calls should be proxied through a Supabase Edge Function so secrets never
/// ship in the app binary; the direct-call setup here is for development.
class Env {
  static String _get(String key) => dotenv.maybeGet(key)?.trim() ?? '';

  static String get supabaseUrl     => _get('SUPABASE_URL');
  static String get supabaseAnonKey => _get('SUPABASE_ANON_KEY');

  static String get defaultCurrency {
    final c = _get('DEFAULT_CURRENCY');
    return c.isEmpty ? 'KES' : c.toUpperCase();
  }

  static bool get hasSupabase =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  /// True when the full scan pipeline can run.
  /// OCR and AI extraction are handled by Supabase Edge Functions,
  /// so only a Supabase connection (and a signed-in user) is required.
  static bool get canScanForReal => hasSupabase;

  /// RevenueCat Google/Android API key (publishable — safe in binary).
  static String get revenueCatGoogleKey => _get('REVENUECAT_GOOGLE_KEY');
  static bool get hasRevenueCat => revenueCatGoogleKey.isNotEmpty;
}
