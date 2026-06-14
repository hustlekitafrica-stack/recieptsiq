/// A business/profile that owns a set of receipts (multi-business support).
class Business {
  final String id;
  final String name;
  final String baseCurrency;

  const Business({
    required this.id,
    required this.name,
    required this.baseCurrency,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'base_currency': baseCurrency,
      };

  factory Business.fromJson(Map<String, dynamic> json) => Business(
        id: json['id'] as String,
        name: json['name'] as String? ?? 'My Money',
        baseCurrency: json['base_currency'] as String? ?? 'KES',
      );
}
