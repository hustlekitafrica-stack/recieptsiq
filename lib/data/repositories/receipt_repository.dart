import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../core/money.dart';
import '../models/budget.dart';
import '../models/category.dart';
import '../models/line_item.dart';
import '../models/receipt.dart';
import 'repository.dart';

/// Persists receipts and budgets locally (shared_preferences).
///
/// Used when Supabase is not configured, and as an offline-friendly default.
class LocalReceiptRepository implements ReceiptRepository {
  static const _receiptsKey = 'receipts_v1';
  static const _budgetsKey = 'budgets_v1';
  static const _seededKey = 'seeded_v1';

  final _uuid = const Uuid();

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  @override
  String newId() => _uuid.v4();

  // ---- Receipts ----

  @override
  Future<List<Receipt>> loadReceipts() async {
    final prefs = await _prefs;
    await _maybeSeed(prefs);
    final raw = prefs.getString(_receiptsKey);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List;
    final receipts = list
        .map((e) => Receipt.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
    receipts.sort((a, b) => b.date.compareTo(a.date));
    return receipts;
  }

  Future<void> _saveReceipts(List<Receipt> receipts) async {
    final prefs = await _prefs;
    final raw = jsonEncode(receipts.map((e) => e.toJson()).toList());
    await prefs.setString(_receiptsKey, raw);
  }

  @override
  Future<List<Receipt>> addReceipt(Receipt receipt) async {
    final receipts = await loadReceipts();
    receipts.insert(0, receipt);
    await _saveReceipts(receipts);
    return receipts;
  }

  @override
  Future<List<Receipt>> updateReceipt(Receipt receipt) async {
    final receipts = await loadReceipts();
    final idx = receipts.indexWhere((r) => r.id == receipt.id);
    if (idx >= 0) receipts[idx] = receipt;
    await _saveReceipts(receipts);
    return receipts;
  }

  @override
  Future<List<Receipt>> deleteReceipt(String id) async {
    final receipts = await loadReceipts();
    receipts.removeWhere((r) => r.id == id);
    await _saveReceipts(receipts);
    return receipts;
  }

  // ---- Budgets ----

  @override
  Future<List<Budget>> loadBudgets() async {
    final prefs = await _prefs;
    final raw = prefs.getString(_budgetsKey);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List;
    return list
        .map((e) => Budget.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  @override
  Future<void> saveBudgets(List<Budget> budgets) async {
    final prefs = await _prefs;
    final raw = jsonEncode(budgets.map((e) => e.toJson()).toList());
    await prefs.setString(_budgetsKey, raw);
  }

  // ---- Data management ----

  /// Wipes all locally stored receipts, budgets, and the seed flag so the
  /// next call to [loadReceipts] starts with a clean slate.
  static Future<void> clearAllData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_receiptsKey);
    await prefs.remove(_budgetsKey);
    await prefs.remove(_seededKey);
  }

  // ---- Seed sample data on first launch so the app isn't empty ----

  Future<void> _maybeSeed(SharedPreferences prefs) async {
    if (prefs.getBool(_seededKey) == true) return;
    final now = DateTime.now();
    Receipt mk(String merchant, int daysAgo, double total,
        ExpenseCategory cat, List<LineItem> items, double? vat) {
      final d = now.subtract(Duration(days: daysAgo));
      return Receipt(
        id: _uuid.v4(),
        businessId: 'default',
        merchant: merchant,
        date: d,
        total: Money(total, 'KES'),
        vat: vat == null ? null : Money(vat, 'KES'),
        category: cat,
        items: items,
        createdAt: d,
      );
    }

    final seed = <Receipt>[
      mk('Naivas', 1, 3250, ExpenseCategory.groceries, const [
        LineItem(name: 'Milk', quantity: 2, unitPrice: 150, amount: 300),
        LineItem(name: 'Bread', quantity: 1, unitPrice: 80, amount: 80),
        LineItem(name: 'Sugar', quantity: 2, unitPrice: 200, amount: 400),
      ], 520),
      mk('Shell', 3, 5000, ExpenseCategory.fuel, const [
        LineItem(name: 'Petrol', quantity: 28, unitPrice: 178, amount: 5000),
      ], 690),
      mk('Java House', 5, 1800, ExpenseCategory.entertainment, const [
        LineItem(name: 'Lunch', quantity: 2, unitPrice: 900, amount: 1800),
      ], 248),
      mk('KPLC', 8, 2400, ExpenseCategory.utilities, const [], 0),
      mk('Carrefour', 12, 6200, ExpenseCategory.groceries, const [
        LineItem(name: 'Rice 5kg', quantity: 1, unitPrice: 950, amount: 950),
        LineItem(name: 'Cooking Oil', quantity: 2, unitPrice: 450, amount: 900),
      ], 990),
      mk('Total Energies', 18, 4500, ExpenseCategory.fuel, const [], 620),
    ];

    await _saveReceipts(seed);
    await saveBudgets([
      Budget(
          id: _uuid.v4(),
          category: ExpenseCategory.groceries,
          limit: 20000,
          currency: 'KES'),
      Budget(
          id: _uuid.v4(),
          category: ExpenseCategory.fuel,
          limit: 10000,
          currency: 'KES'),
    ]);
    await prefs.setBool(_seededKey, true);
  }
}
