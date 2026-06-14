import 'package:intl/intl.dart';

/// Supported currencies for the multi-currency MVP.
/// Code -> human label. Symbols are resolved via [currencySymbol].
const Map<String, String> kSupportedCurrencies = {
  'KES': 'Kenyan Shilling',
  'UGX': 'Ugandan Shilling',
  'TZS': 'Tanzanian Shilling',
  'NGN': 'Nigerian Naira',
  'GHS': 'Ghanaian Cedi',
  'ZAR': 'South African Rand',
  'USD': 'US Dollar',
  'EUR': 'Euro',
  'GBP': 'British Pound',
};

const Map<String, String> _currencySymbols = {
  'KES': 'Ksh',
  'UGX': 'USh',
  'TZS': 'TSh',
  'NGN': '₦',
  'GHS': 'GH₵',
  'ZAR': 'R',
  'USD': '\$',
  'EUR': '€',
  'GBP': '£',
};

String currencySymbol(String code) => _currencySymbols[code] ?? code;

/// A money value that always carries its currency, so receipts captured in
/// different currencies can coexist (multi-currency support).
class Money {
  final double amount;
  final String currency;

  const Money(this.amount, this.currency);

  const Money.zero(this.currency) : amount = 0;

  Money copyWith({double? amount, String? currency}) =>
      Money(amount ?? this.amount, currency ?? this.currency);

  String format({bool withSymbol = true}) {
    final symbol = currencySymbol(currency);
    final formatter = NumberFormat.currency(
      symbol: withSymbol ? '$symbol ' : '',
      decimalDigits: _decimalDigits(currency),
    );
    return formatter.format(amount).trim();
  }

  static int _decimalDigits(String code) {
    // Zero-decimal currencies common in the region.
    const zeroDecimal = {'KES', 'UGX', 'TZS'};
    return zeroDecimal.contains(code) ? 0 : 2;
  }

  Map<String, dynamic> toJson() => {'amount': amount, 'currency': currency};

  factory Money.fromJson(Map<String, dynamic> json) => Money(
        (json['amount'] as num?)?.toDouble() ?? 0,
        json['currency'] as String? ?? 'KES',
      );

  @override
  String toString() => format();
}
