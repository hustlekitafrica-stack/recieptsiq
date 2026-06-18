class Budget {
  final double amount;
  final String currency;

  const Budget({required this.amount, required this.currency});

  Map<String, dynamic> toJson() => {'amount': amount, 'currency': currency};

  factory Budget.fromJson(Map<String, dynamic> json) => Budget(
        amount: (json['amount'] as num).toDouble(),
        currency: json['currency'] as String? ?? 'KES',
      );
}
