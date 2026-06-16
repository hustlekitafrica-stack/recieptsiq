import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/monthly_review.dart';
import '../models/receipt.dart';
import '../models/yearly_review.dart';
import 'repository.dart';

/// Persists receipts locally (shared_preferences).
///
/// Used when Supabase is not configured, and as an offline-friendly default.
class LocalReceiptRepository implements ReceiptRepository {
  static const _receiptsKey = 'receipts_v1';
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

  // ---- Review cache ----

  @override
  Future<MonthlyReview?> loadMonthlyReviewCache(String yearMonth) async {
    final prefs = await _prefs;
    final raw = prefs.getString('anon_review_cache_$yearMonth');
    if (raw == null) return null;
    try {
      return MonthlyReview.fromJson(
          jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> saveMonthlyReviewCache(
      String yearMonth, MonthlyReview review) async {
    final prefs = await _prefs;
    await prefs.setString(
        'anon_review_cache_$yearMonth', jsonEncode(review.toJson()));
  }

  @override
  Future<void> clearMonthlyReviewCache(String yearMonth) async {
    final prefs = await _prefs;
    await prefs.remove('anon_review_cache_$yearMonth');
  }

  @override
  Future<YearlyReview?> loadYearlyReviewCache(int year) async {
    final prefs = await _prefs;
    final raw = prefs.getString('anon_yearly_cache_$year');
    if (raw == null) return null;
    try {
      return YearlyReview.fromJson(
          jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> saveYearlyReviewCache(int year, YearlyReview review) async {
    final prefs = await _prefs;
    await prefs.setString('anon_yearly_cache_$year', jsonEncode(review.toJson()));
  }

  // ---- Data management ----

  /// Wipes all locally stored receipts and the seed flag so the
  /// next call to [loadReceipts] starts with a clean slate.
  static Future<void> clearAllData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_receiptsKey);
    await prefs.remove(_seededKey);
  }

  Future<void> _maybeSeed(SharedPreferences prefs) async {
    await prefs.setBool(_seededKey, true);
  }
}
