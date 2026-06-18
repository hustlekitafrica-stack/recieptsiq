import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'budget_model.dart';

class BudgetRepository {
  static const _key = 'monthly_budget_v1';

  Future<Budget?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return null;
    try {
      return Budget.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> save(Budget budget) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(budget.toJson()));
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
