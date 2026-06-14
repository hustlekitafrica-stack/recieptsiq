import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Centralised access to runtime configuration loaded from the `.env` asset.
///
/// Keys are intentionally NOT hardcoded in source. For production, OCR/LLM
/// calls should be proxied through a Supabase Edge Function so secrets never
/// ship in the app binary; the direct-call setup here is for development.
class Env {
  static String _get(String key) => dotenv.maybeGet(key)?.trim() ?? '';

  static String get supabaseUrl => _get('SUPABASE_URL');
  static String get supabaseAnonKey => _get('SUPABASE_ANON_KEY');
  static String get googleVisionApiKey => _get('GOOGLE_VISION_API_KEY');
  static String get openAiApiKey => _get('OPENAI_API_KEY');

  static String get openAiModel {
    final m = _get('OPENAI_MODEL');
    return m.isEmpty ? 'gpt-4o-mini' : m;
  }

  static String get defaultCurrency {
    final c = _get('DEFAULT_CURRENCY');
    return c.isEmpty ? 'KES' : c.toUpperCase();
  }

  static bool get hasSupabase =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
  static bool get hasVision => googleVisionApiKey.isNotEmpty;
  static bool get hasOpenAi => openAiApiKey.isNotEmpty;

  /// True when the full scan pipeline (OCR + extraction) can run for real.
  static bool get canScanForReal => hasVision && hasOpenAi;
}
