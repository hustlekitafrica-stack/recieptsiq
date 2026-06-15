import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/env.dart';
import '../money.dart';
import '../../data/models/budget.dart';
import '../../data/models/category.dart';
import '../../data/models/monthly_review.dart';
import '../../data/models/receipt_draft.dart';
import '../../features/dashboard/analytics.dart';

class ExtractionException implements Exception {
  final String message;
  ExtractionException(this.message);
  @override
  String toString() => 'ExtractionException: $message';
}

/// Turns raw OCR text into structured receipt data via the [scan/extract]
/// Supabase Edge Function, and generates monthly AI reviews via
/// [scan/monthly-review]. All API keys live server-side.
class ExtractionService {
  SupabaseClient get _sb => Supabase.instance.client;

  // ── Receipt extraction ─────────────────────────────────────────────────────

  Future<ReceiptDraft> extract(String ocrText,
      {required String fallbackCurrency}) async {
    try {
      final res = await _sb.functions.invoke(
        'scan-extract',
        body: {'ocr_text': ocrText, 'currency': fallbackCurrency},
      );
      final data = res.data as Map?;
      if (data?['error'] != null) {
        throw ExtractionException(data!['error'].toString());
      }
      final parsed = Map<String, dynamic>.from(data!);
      return ReceiptDraft.fromExtraction(parsed,
          fallbackCurrency: fallbackCurrency)
        ..rawText = ocrText;
    } on FunctionException catch (e) {
      throw ExtractionException('Extraction request failed: ${e.details}');
    } catch (e) {
      if (e is ExtractionException) rethrow;
      throw ExtractionException('Extraction request failed: $e');
    }
  }

  // ── AI Monthly Review ──────────────────────────────────────────────────────

  /// Generates a personalised monthly financial review via the
  /// [scan/monthly-review] Edge Function.
  /// Returns `null` when Supabase is not configured (local/offline mode).
  Future<MonthlyReview?> generateMonthlyReview({
    required SpendingAnalytics analytics,
    required List<Budget> budgets,
    required String currency,
    required String monthLabel,
  }) async {
    if (!Env.hasSupabase) return null;

    final breakdown = analytics.byCategory.entries
        .map((e) => '${e.key.label} ${Money(e.value, currency).format()}')
        .join(', ');

    final budgetStatus = budgets.isEmpty
        ? 'No budgets set.'
        : budgets.map((b) {
            final used = analytics.byCategory[b.category] ?? 0;
            final pct = b.limit > 0 ? (used / b.limit * 100).round() : 0;
            return '${b.category.label}: ${Money(used, currency).format()} of '
                '${Money(b.limit, b.currency).format()} ($pct%)';
          }).join('\n');

    try {
      final res = await _sb.functions.invoke(
        'scan-monthly-review',
        body: {
          'month_label':             monthLabel,
          'currency':                currency,
          'total_spent':             analytics.monthlySpend,
          'receipt_count':           analytics.receiptCount,
          'biggest_category':        analytics.biggestCategory?.label,
          'biggest_category_amount': analytics.biggestCategoryAmount,
          'category_breakdown':      breakdown,
          'budget_status':           budgetStatus,
        },
      );
      final data = res.data as Map?;
      if (data?['error'] != null) return null;
      return MonthlyReview.fromJson(Map<String, dynamic>.from(data!));
    } catch (_) {
      return null;
    }
  }
}
