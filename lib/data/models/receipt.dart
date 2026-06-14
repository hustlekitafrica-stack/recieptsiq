import '../../core/money.dart';
import 'category.dart';
import 'line_item.dart';

/// A fully parsed receipt: the core unit of the app.
class Receipt {
  final String id;
  final String businessId;
  final String merchant;
  final DateTime date;
  final Money total;
  final Money? vat;
  final ExpenseCategory category;
  final List<LineItem> items;
  final String? imagePath;
  final String? rawText;
  final String? notes;
  final DateTime createdAt;

  const Receipt({
    required this.id,
    required this.businessId,
    required this.merchant,
    required this.date,
    required this.total,
    required this.category,
    this.vat,
    this.items = const [],
    this.imagePath,
    this.rawText,
    this.notes,
    required this.createdAt,
  });

  String get currency => total.currency;

  Receipt copyWith({
    String? merchant,
    DateTime? date,
    Money? total,
    Money? vat,
    ExpenseCategory? category,
    List<LineItem>? items,
    String? imagePath,
    String? notes,
  }) =>
      Receipt(
        id: id,
        businessId: businessId,
        merchant: merchant ?? this.merchant,
        date: date ?? this.date,
        total: total ?? this.total,
        vat: vat ?? this.vat,
        category: category ?? this.category,
        items: items ?? this.items,
        imagePath: imagePath ?? this.imagePath,
        rawText: rawText,
        notes: notes ?? this.notes,
        createdAt: createdAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'business_id': businessId,
        'merchant': merchant,
        'date': date.toIso8601String(),
        'total': total.toJson(),
        'vat': vat?.toJson(),
        'category': category.key,
        'items': items.map((e) => e.toJson()).toList(),
        'image_path': imagePath,
        'raw_text': rawText,
        'notes': notes,
        'created_at': createdAt.toIso8601String(),
      };

  factory Receipt.fromJson(Map<String, dynamic> json) => Receipt(
        id: json['id'] as String,
        businessId: json['business_id'] as String? ?? 'default',
        merchant: json['merchant'] as String? ?? 'Unknown',
        date: DateTime.tryParse(json['date'] as String? ?? '') ??
            DateTime.now(),
        total: Money.fromJson(
            (json['total'] as Map).cast<String, dynamic>()),
        vat: json['vat'] == null
            ? null
            : Money.fromJson((json['vat'] as Map).cast<String, dynamic>()),
        category: ExpenseCategoryX.fromKey(json['category'] as String?),
        items: (json['items'] as List? ?? [])
            .map((e) => LineItem.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
        imagePath: json['image_path'] as String?,
        rawText: json['raw_text'] as String?,
        notes: json['notes'] as String?,
        createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
            DateTime.now(),
      );
}
