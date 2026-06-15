import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/env.dart';
import '../money.dart';
import '../../data/models/category.dart';
import '../../data/models/monthly_review.dart';
import '../../data/models/receipt_draft.dart';
import '../../data/models/yearly_review.dart';
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
    required String currency,
    required String monthLabel,
  }) async {
    if (!Env.hasSupabase) return null;

    final breakdown = analytics.byCategory.entries
        .map((e) => '${e.key.label} ${Money(e.value, currency).format()}')
        .join(', ');

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
        },
      );
      final data = res.data as Map?;
      if (data?['error'] != null) return null;
      return MonthlyReview.fromJson(Map<String, dynamic>.from(data!));
    } catch (_) {
      return null;
    }
  }

  // ── AI Yearly Review ───────────────────────────────────────────────────────

  /// Generates a year-in-review via the [scan/monthly-review] edge function
  /// with a yearly context payload. Returns `null` when Supabase is not
  /// configured or the call fails.
  Future<YearlyReview?> generateYearlyReview({
    required YearlyAnalytics analytics,
    required String currency,
  }) async {
    if (!Env.hasSupabase) return null;

    final breakdown = analytics.byCategory.entries
        .map((e) => '${e.key.label} ${Money(e.value, currency).format()}')
        .join(', ');

    final monthNames = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];

    try {
      final res = await _sb.functions.invoke(
        'scan-monthly-review',
        body: {
          'month_label': 'Full year ${analytics.year}',
          'currency': currency,
          'total_spent': analytics.totalSpend,
          'receipt_count': analytics.receiptCount,
          'biggest_category': analytics.byCategory.entries.isEmpty
              ? null
              : (analytics.byCategory.entries.toList()
                    ..sort((a, b) => b.value.compareTo(a.value)))
                  .first
                  .key
                  .label,
          'biggest_category_amount': analytics.byCategory.values.isEmpty
              ? 0
              : analytics.byCategory.values.reduce((a, b) => a > b ? a : b),
          'category_breakdown': breakdown,
          'budget_status':
              'Best month: ${monthNames[analytics.bestMonth]}, '
              'worst month: ${monthNames[analytics.worstMonth]}. '
              'YoY change: ${analytics.yearOverYearChange?.toStringAsFixed(1) ?? 'N/A'}%.',
        },
      );
      final data = res.data as Map?;
      if (data?['error'] != null) return null;
      final review = MonthlyReview.fromJson(Map<String, dynamic>.from(data!));
      return YearlyReview(
        year: analytics.year,
        totalSpend: analytics.totalSpend,
        monthlyTotals: analytics.monthlyTotals,
        byCategory: analytics.byCategory,
        topMerchants: analytics.topMerchants,
        bestMonth: analytics.bestMonth,
        worstMonth: analytics.worstMonth,
        receiptCount: analytics.receiptCount,
        yearOverYearChange: analytics.yearOverYearChange,
        headline: review.headline,
        summary: review.summary,
        savingsOpportunities: [...review.insights, ...review.tips],
      );
    } catch (_) {
      return null;
    }
  }
}
