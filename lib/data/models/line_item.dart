import 'category.dart';

/// A single line on a receipt (e.g. "Milk x2 = 300").
class LineItem {
  final String name;
  final double quantity;
  final double unitPrice;
  final double amount;
  final Category? category;

  const LineItem({
    required this.name,
    this.quantity = 1,
    this.unitPrice = 0,
    this.amount = 0,
    this.category,
  });

  LineItem copyWith({
    String? name,
    double? quantity,
    double? unitPrice,
    double? amount,
    Category? category,
  }) =>
      LineItem(
        name: name ?? this.name,
        quantity: quantity ?? this.quantity,
        unitPrice: unitPrice ?? this.unitPrice,
        amount: amount ?? this.amount,
        category: category ?? this.category,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'quantity': quantity,
        'unit_price': unitPrice,
        'amount': amount,
        if (category != null) 'category': category!.key,
      };

  factory LineItem.fromJson(Map<String, dynamic> json) {
    final rawUnit = json['unit_price'] ?? json['unitPrice'];
    return LineItem(
      name: (json['name'] ?? '').toString(),
      quantity: (json['quantity'] as num?)?.toDouble() ?? 1,
      unitPrice: (rawUnit as num?)?.toDouble() ?? 0,
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      category: json['category'] != null
          ? Category.fromKey(json['category'] as String?)
          : null,
    );
  }
}
