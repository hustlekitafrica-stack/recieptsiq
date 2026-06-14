// Unit tests for ReceiptIQ core logic.

import 'package:flutter_test/flutter_test.dart';
import 'package:receiptiq/core/money.dart';
import 'package:receiptiq/data/models/category.dart';
import 'package:receiptiq/data/models/receipt.dart';
import 'package:receiptiq/features/dashboard/analytics.dart';

Receipt _mk(String merchant, ExpenseCategory cat, double amount, DateTime d) {
  return Receipt(
    id: merchant,
    businessId: 'default',
    merchant: merchant,
    date: d,
    total: Money(amount, 'KES'),
    category: cat,
    createdAt: d,
  );
}

void main() {
  test('Money formats zero-decimal currencies without decimals', () {
    expect(const Money(3250, 'KES').format(), 'Ksh 3,250');
    expect(const Money(10.5, 'USD').format(), '\$ 10.50');
  });

  test('Category maps from key with safe fallback', () {
    expect(ExpenseCategoryX.fromKey('fuel'), ExpenseCategory.fuel);
    expect(ExpenseCategoryX.fromKey('nonsense'), ExpenseCategory.other);
  });

  test('Analytics computes monthly total and biggest category', () {
    final now = DateTime(2026, 6, 15);
    final receipts = [
      _mk('Naivas', ExpenseCategory.groceries, 3000, now),
      _mk('Shell', ExpenseCategory.fuel, 6000, now),
      _mk('Carrefour', ExpenseCategory.groceries, 2000, now),
    ];
    final a = SpendingAnalytics.compute(receipts, now: now);
    expect(a.monthlySpend, 11000);
    expect(a.biggestCategory, ExpenseCategory.fuel);
    expect(a.receiptCount, 3);
  });
}
