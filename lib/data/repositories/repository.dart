import '../models/monthly_review.dart';
import '../models/receipt.dart';
import '../models/yearly_review.dart';

/// Storage abstraction so the UI/state layer is agnostic to where data lives
/// (local shared_preferences vs Supabase Postgres + Storage).
abstract class ReceiptRepository {
  String newId();

  Future<List<Receipt>> loadReceipts();
  Future<List<Receipt>> addReceipt(Receipt receipt);
  Future<List<Receipt>> updateReceipt(Receipt receipt);
  Future<List<Receipt>> deleteReceipt(String id);

  // ---- Review cache ----
  Future<MonthlyReview?> loadMonthlyReviewCache(String yearMonth);
  Future<void> saveMonthlyReviewCache(String yearMonth, MonthlyReview review);
  Future<YearlyReview?> loadYearlyReviewCache(int year);
  Future<void> saveYearlyReviewCache(int year, YearlyReview review);
}
