/// A single line on a receipt (e.g. "Milk x2 = 300").
class LineItem {
  final String name;
  final double quantity;
  final double unitPrice;
  final double amount;

  const LineItem({
    required this.name,
    this.quantity = 1,
    this.unitPrice = 0,
    this.amount = 0,
  });

  LineItem copyWith({
    String? name,
    double? quantity,
    double? unitPrice,
    double? amount,
  }) =>
      LineItem(
        name: name ?? this.name,
        quantity: quantity ?? this.quantity,
        unitPrice: unitPrice ?? this.unitPrice,
        amount: amount ?? this.amount,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'quantity': quantity,
        'unit_price': unitPrice,
        'amount': amount,
      };

  factory LineItem.fromJson(Map<String, dynamic> json) {
    final rawUnit = json['unit_price'] ?? json['unitPrice'];
    return LineItem(
      name: (json['name'] ?? '').toString(),
      quantity: (json['quantity'] as num?)?.toDouble() ?? 1,
      unitPrice: (rawUnit as num?)?.toDouble() ?? 0,
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
    );
  }
}
