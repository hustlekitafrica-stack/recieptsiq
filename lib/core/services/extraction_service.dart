import 'dart:convert';

import 'package:dio/dio.dart';

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

/// Turns raw receipt OCR text into structured data using an OpenAI model.
///
/// Uses JSON-mode for reliable, cheap, schema-shaped output.
class ExtractionService {
  final Dio _dio;
  ExtractionService([Dio? dio]) : _dio = dio ?? Dio();

  static const _endpoint = 'https://api.openai.com/v1/chat/completions';

  static const _categories =
      'groceries, fuel, rent, utilities, transport, entertainment, '
      'businessSupplies, staffExpenses, school, medical, other';

  String _systemPrompt(String fallbackCurrency) => '''
You are an expert at reading shopping/business receipts and returning STRICT JSON.
Extract the fields below from the receipt text. Respond with ONLY a JSON object, no prose.

Schema:
{
  "merchant": string,           // store/business name
  "date": string,               // ISO 8601 date (YYYY-MM-DD), best guess from receipt
  "total": number,              // grand total amount
  "vat": number|null,           // tax/VAT amount if present, else null
  "currency": string,           // ISO 4217 code (e.g. KES, USD, NGN). Default "$fallbackCurrency" if unknown
  "category": string,           // one of: $_categories
  "items": [
    { "name": string, "quantity": number, "unit_price": number, "amount": number }
  ]
}

Rules:
- Numbers must be plain numbers (no currency symbols, no thousands separators).
- If a field is missing, use a sensible default (0, null, or "$fallbackCurrency").
- Pick the single best category from the allowed list.
''';

  Future<ReceiptDraft> extract(String ocrText,
      {required String fallbackCurrency}) async {
    if (!Env.hasOpenAi) {
      throw ExtractionException('OpenAI API key is not configured.');
    }

    try {
      final response = await _dio.post(
        _endpoint,
        options: Options(headers: {
          'Authorization': 'Bearer ${Env.openAiApiKey}',
          'Content-Type': 'application/json',
        }),
        data: {
          'model': Env.openAiModel,
          'temperature': 0,
          'response_format': {'type': 'json_object'},
          'messages': [
            {'role': 'system', 'content': _systemPrompt(fallbackCurrency)},
            {'role': 'user', 'content': 'Receipt text:\n"""\n$ocrText\n"""'}
          ],
        },
      );

      final content =
          response.data['choices']?[0]?['message']?['content'] as String?;
      if (content == null || content.trim().isEmpty) {
        throw ExtractionException('AI returned an empty response.');
      }

      final parsed = jsonDecode(content) as Map<String, dynamic>;
      return ReceiptDraft.fromExtraction(parsed,
          fallbackCurrency: fallbackCurrency)
        ..rawText = ocrText;
    } on DioException catch (e) {
      final msg = e.response?.data is Map
          ? (e.response?.data['error']?['message']?.toString() ?? e.message)
          : e.message;
      throw ExtractionException('Extraction request failed: $msg');
    } on FormatException {
      throw ExtractionException('AI returned malformed JSON.');
    }
  }

  // ---- Monthly review generation (AI Financial Coach) ----

  /// Generates a personalised monthly financial review from the user's
  /// spending analytics and budgets. Returns `null` when OpenAI is not
  /// configured so the UI can fall back to rule-based insights.
  Future<MonthlyReview?> generateMonthlyReview({
    required SpendingAnalytics analytics,
    required List<Budget> budgets,
    required String currency,
    required String monthLabel,
  }) async {
    if (!Env.hasOpenAi) return null;

    final breakdown = analytics.byCategory.entries
        .map((e) => '${e.key.label} ${Money(e.value, currency).format()}')
        .join(', ');

    final budgetLines = budgets.map((b) {
      final used = analytics.byCategory[b.category] ?? 0;
      final pct = b.limit > 0 ? (used / b.limit * 100).round() : 0;
      return '${b.category.label}: ${Money(used, currency).format()} of '
          '${Money(b.limit, b.currency).format()} ($pct%)';
    }).join('\n');

    final prompt = '''
You are ReceiptIQ's AI Financial Coach. Generate a friendly, encouraging monthly financial review for a user in East Africa.

User data for $monthLabel:
- Total spent: ${Money(analytics.monthlySpend, currency).format()}
- Receipts: ${analytics.receiptCount}
- Biggest category: ${analytics.biggestCategory?.label ?? '—'} (${Money(analytics.biggestCategoryAmount, currency).format()})
- Category breakdown: $breakdown
- Budget status:
$budgetLines

Rules:
- Be encouraging and practical, never shaming.
- Highlight one positive trend or win.
- Flag any budget overruns gently.
- Give 2–3 actionable, specific tips.
- Keep total review under 180 words.
- Use local context when relevant (Kenya / Tanzania / Uganda / Nigeria / Ghana).

Return JSON with this exact schema:
{
  "headline": "string (catchy one-line headline)",
  "summary": "string (2-3 sentence overview)",
  "insights": ["string", "string", "..."],
  "tips": ["string", "string", "string"],
  "budget_alerts": ["string", "..."],
  "tone": "positive|neutral|caution"
}
''';

    try {
      final response = await _dio.post(
        _endpoint,
        options: Options(headers: {
          'Authorization': 'Bearer ${Env.openAiApiKey}',
          'Content-Type': 'application/json',
        }),
        data: {
          'model': Env.openAiModel,
          'temperature': 0.4,
          'response_format': {'type': 'json_object'},
          'messages': [
            {'role': 'system', 'content': prompt},
          ],
        },
      );

      final content =
          response.data['choices']?[0]?['message']?['content'] as String?;
      if (content == null || content.trim().isEmpty) return null;
      return MonthlyReview.fromJson(
          jsonDecode(content) as Map<String, dynamic>);
    } on DioException catch (e) {
      final msg = e.response?.data is Map
          ? (e.response?.data['error']?['message']?.toString() ?? e.message)
          : e.message;
      throw ExtractionException('Review generation failed: $msg');
    } on FormatException {
      throw ExtractionException('Review AI returned malformed JSON.');
    }
  }
}
