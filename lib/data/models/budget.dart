import 'category.dart';

/// A monthly spending limit for a category.
class Budget {
  final String id;
  final ExpenseCategory category;
  final double limit;
  final String currency;

  const Budget({
    required this.id,
    required this.category,
    required this.limit,
    required this.currency,
  });

  Budget copyWith({double? limit}) => Budget(
        id: id,
        category: category,
        limit: limit ?? this.limit,
        currency: currency,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'category': category.key,
        'limit': limit,
        'currency': currency,
      };

  factory Budget.fromJson(Map<String, dynamic> json) => Budget(
        id: json['id'] as String,
        category: ExpenseCategoryX.fromKey(json['category'] as String?),
        limit: (json['limit'] as num?)?.toDouble() ?? 0,
        currency: json['currency'] as String? ?? 'KES',
      );
}
