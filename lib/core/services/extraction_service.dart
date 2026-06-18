import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/env.dart';
import '../money.dart';
import '../../data/models/monthly_review.dart';
import '../../data/models/receipt.dart';
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

  // ── AI Chat ────────────────────────────────────────────────────────────────

  /// Sends a natural-language question to the [scan-chat] Edge Function with
  /// the user's receipt context. Returns `null` when offline or on failure.
  Future<String?> askQuestion({
    required String message,
    required List<Receipt> receipts,
    required String currency,
  }) async {
    if (!Env.hasSupabase) return null;

    final context = receipts.take(200).map((r) => {
          'date': DateFormat('yyyy-MM-dd').format(r.date),
          'merchant': r.merchant,
          'amount': r.total.amount,
          'currency': r.total.currency,
          'category': r.category.label,
        }).toList();

    try {
      final res = await _sb.functions.invoke(
        'scan-chat',
        body: {
          'message': message,
          'currency': currency,
          'receipt_context': context,
        },
      );
      final data = res.data as Map?;
      if (data?['error'] != null) {
        return _localAnswer(message: message, receipts: receipts, currency: currency);
      }
      return data?['reply'] as String?;
    } catch (_) {
      return _localAnswer(message: message, receipts: receipts, currency: currency);
    }
  }

  /// Rule-based fallback when the edge function is unavailable.
  String _localAnswer({
    required String message,
    required List<Receipt> receipts,
    required String currency,
  }) {
    if (receipts.isEmpty) {
      return 'No receipt data found. Scan some receipts first and I\'ll be able to answer your questions.';
    }

    final q = message.toLowerCase();
    final now = DateTime.now();

    // Helpers
    final thisMonth = receipts
        .where((r) => r.date.year == now.year && r.date.month == now.month)
        .toList();
    final lm = DateTime(now.year, now.month - 1);
    final lastMonth = receipts
        .where((r) => r.date.year == lm.year && r.date.month == lm.month)
        .toList();

    double sum(List<Receipt> list) =>
        list.fold(0, (s, r) => s + r.total.amount);

    String fmt(double v) => Money(v, currency).format();

    // ── This month total ──────────────────────────────────────────────────
    if ((q.contains('this month') || q.contains('current month')) &&
        (q.contains('spend') || q.contains('spent') || q.contains('total'))) {
      final total = sum(thisMonth);
      return thisMonth.isEmpty
          ? 'No receipts recorded yet this month.'
          : 'You have spent ${fmt(total)} this month across ${thisMonth.length} receipt${thisMonth.length == 1 ? '' : 's'}.';
    }

    // ── Last month total ──────────────────────────────────────────────────
    if (q.contains('last month') &&
        (q.contains('spend') || q.contains('spent') || q.contains('total'))) {
      final total = sum(lastMonth);
      return lastMonth.isEmpty
          ? 'No receipts found for last month.'
          : 'You spent ${fmt(total)} last month across ${lastMonth.length} receipt${lastMonth.length == 1 ? '' : 's'}.';
    }

    // ── All-time total ────────────────────────────────────────────────────
    if ((q.contains('total') || q.contains('all time') || q.contains('ever') || q.contains('overall')) &&
        (q.contains('spend') || q.contains('spent'))) {
      final total = sum(receipts);
      return 'Your total all-time spending is ${fmt(total)} across ${receipts.length} receipts.';
    }

    // ── Top supplier / merchant ───────────────────────────────────────────
    if (q.contains('supplier') || q.contains('merchant') ||
        (q.contains('most') && (q.contains('cost') || q.contains('expensive') || q.contains('spend')))) {
      final byMerchant = <String, double>{};
      for (final r in receipts) {
        byMerchant.update(r.merchant, (v) => v + r.total.amount,
            ifAbsent: () => r.total.amount);
      }
      if (byMerchant.isEmpty) return 'No merchant data available yet.';
      final top = byMerchant.entries.reduce((a, b) => a.value >= b.value ? a : b);
      final sorted = byMerchant.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final topThree = sorted.take(3).map((e) => '${e.key}: ${fmt(e.value)}').join(', ');
      return 'Your biggest supplier is ${top.key} at ${fmt(top.value)} total. '
          'Top 3: $topThree.';
    }

    // ── Category spending ─────────────────────────────────────────────────
    if (q.contains('categor') || q.contains('what') && q.contains('on') ||
        q.contains('biggest expense') || q.contains('most spend')) {
      final byCat = <String, double>{};
      for (final r in receipts) {
        byCat.update(r.category.label, (v) => v + r.total.amount,
            ifAbsent: () => r.total.amount);
      }
      if (byCat.isEmpty) return 'No category data available yet.';
      final top = byCat.entries.reduce((a, b) => a.value >= b.value ? a : b);
      final total = sum(receipts);
      final pct = total > 0 ? (top.value / total * 100).toStringAsFixed(0) : '0';
      return 'Your biggest expense category is ${top.key} at ${fmt(top.value)} ($pct% of total spending).';
    }

    // ── Trend / comparison ───────────────────────────────────────────────
    if (q.contains('trend') || q.contains('compar') || q.contains('more') || q.contains('less')) {
      final thisTotal = sum(thisMonth);
      final lastTotal = sum(lastMonth);
      if (lastTotal <= 0) {
        return 'Not enough monthly history to show a trend yet.';
      }
      final diff = thisTotal - lastTotal;
      final pct = (diff / lastTotal * 100).abs().toStringAsFixed(0);
      final direction = diff >= 0 ? 'up' : 'down';
      return 'This month you\'ve spent ${fmt(thisTotal)}, which is $direction $pct% compared to last month\'s ${fmt(lastTotal)}.';
    }

    // ── Average spend ─────────────────────────────────────────────────────
    if (q.contains('average') || q.contains('avg')) {
      final months = receipts.map((r) => '${r.date.year}-${r.date.month}').toSet();
      if (months.isEmpty) return 'No data to calculate an average.';
      final avg = sum(receipts) / months.length;
      return 'Your average monthly spending is ${fmt(avg)} based on ${months.length} month${months.length == 1 ? '' : 's'} of data.';
    }

    // ── Receipt count ─────────────────────────────────────────────────────
    if (q.contains('how many') && (q.contains('receipt') || q.contains('scan'))) {
      return 'You have ${receipts.length} receipt${receipts.length == 1 ? '' : 's'} in total. '
          '${thisMonth.length} this month.';
    }

    // ── Generic fallback ─────────────────────────────────────────────────
    final thisTotal = sum(thisMonth);
    final byCat = <String, double>{};
    for (final r in receipts) {
      byCat.update(r.category.label, (v) => v + r.total.amount,
          ifAbsent: () => r.total.amount);
    }
    final topCat = byCat.isEmpty
        ? 'N/A'
        : byCat.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    return 'You have ${receipts.length} receipts totalling ${fmt(sum(receipts))}. '
        'This month: ${fmt(thisTotal)} across ${thisMonth.length} receipt${thisMonth.length == 1 ? '' : 's'}. '
        'Biggest category: $topCat. '
        'Try asking about spending trends, top suppliers, or category breakdowns.';
  }
}
