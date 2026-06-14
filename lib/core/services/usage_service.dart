import 'package:shared_preferences/shared_preferences.dart';

/// Tracks how many AI scans the user has performed this calendar month.
/// The counter is stored in SharedPreferences and resets automatically when
/// the calendar month changes. No network call is required to enforce limits.
class UsageService {
  static const _keyScans = 'usage_scans_count';
  static const _keyMonth = 'usage_scans_month';

  final SharedPreferences _prefs;
  UsageService(this._prefs);

  /// Current year-month string used as the bucket key, e.g. "2025-06".
  static String _currentBucket() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}';
  }

  /// Scans performed in the current calendar month.
  int get scansThisMonth {
    _resetIfNewMonth();
    return _prefs.getInt(_keyScans) ?? 0;
  }

  /// Returns true when the user is allowed to perform another scan.
  /// [maxScans] == -1 means unlimited (Pro tier).
  bool canScan(int maxScans) {
    if (maxScans < 0) return true;
    return scansThisMonth < maxScans;
  }

  /// Call this after a successful scan to increment the counter.
  Future<void> recordScan() async {
    _resetIfNewMonth();
    final current = _prefs.getInt(_keyScans) ?? 0;
    await _prefs.setInt(_keyScans, current + 1);
  }

  /// Resets the counter if we have rolled into a new calendar month.
  void _resetIfNewMonth() {
    final bucket = _currentBucket();
    final saved = _prefs.getString(_keyMonth) ?? '';
    if (saved != bucket) {
      _prefs.setInt(_keyScans, 0);
      _prefs.setString(_keyMonth, bucket);
    }
  }

  /// For testing: reset the counter to zero.
  Future<void> reset() async {
    await _prefs.setInt(_keyScans, 0);
    await _prefs.setString(_keyMonth, _currentBucket());
  }

  /// Clears all stored usage data.
  Future<void> clearAll() async {
    await _prefs.remove(_keyScans);
    await _prefs.remove(_keyMonth);
  }
}
