import '../models/budget.dart';
import '../models/receipt.dart';

/// Storage abstraction so the UI/state layer is agnostic to where data lives
/// (local shared_preferences vs Supabase Postgres + Storage).
abstract class ReceiptRepository {
  String newId();

  Future<List<Receipt>> loadReceipts();
  Future<List<Receipt>> addReceipt(Receipt receipt);
  Future<List<Receipt>> updateReceipt(Receipt receipt);
  Future<List<Receipt>> deleteReceipt(String id);

  Future<List<Budget>> loadBudgets();
  Future<void> saveBudgets(List<Budget> budgets);
}
