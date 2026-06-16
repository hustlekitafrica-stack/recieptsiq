import 'category.dart';
import 'line_item.dart';

/// Editable, not-yet-saved result of OCR + AI extraction.
/// The user reviews/edits this before it becomes a [Receipt].
class ReceiptDraft {
  String merchant;
  DateTime date;
  double total;
  double? vat;
  String currency;
  Category category;
  List<LineItem> items;
  String? rawText;
  String? imagePath;

  ReceiptDraft({
    required this.merchant,
    required this.date,
    required this.total,
    required this.currency,
    required this.category,
    this.vat,
    this.items = const [],
    this.rawText,
    this.imagePath,
  });

  factory ReceiptDraft.empty(String currency) => ReceiptDraft(
        merchant: '',
        date: DateTime.now(),
        total: 0,
        currency: currency,
        category: Category.other,
        items: [],
      );

  /// Builds a draft from the structured JSON returned by the LLM.
  factory ReceiptDraft.fromExtraction(
    Map<String, dynamic> json, {
    required String fallbackCurrency,
  }) {
    DateTime parseDate(dynamic raw) {
      if (raw is String && raw.isNotEmpty) {
        return DateTime.tryParse(raw) ?? DateTime.now();
      }
      return DateTime.now();
    }

    final items = (json['items'] as List? ?? [])
        .whereType<Map>()
        .map((e) => LineItem.fromJson(e.cast<String, dynamic>()))
        .toList();

    final currencyRaw = (json['currency'] as String?)?.trim();

    return ReceiptDraft(
      merchant: (json['merchant'] as String?)?.trim().isNotEmpty == true
          ? (json['merchant'] as String).trim()
          : 'Unknown merchant',
      date: parseDate(json['date']),
      total: (json['total'] as num?)?.toDouble() ?? 0,
      vat: (json['vat'] as num?)?.toDouble(),
      currency: (currencyRaw != null && currencyRaw.isNotEmpty)
          ? currencyRaw.toUpperCase()
          : fallbackCurrency,
      category: Category.fromKey(json['category'] as String?),
      items: items,
    );
  }
}
