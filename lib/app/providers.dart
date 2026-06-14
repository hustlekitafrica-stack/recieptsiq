import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/env.dart';
import '../core/services/extraction_service.dart';
import '../core/services/ocr_service.dart';
import '../data/models/budget.dart';
import '../data/models/monthly_review.dart';
import '../data/models/receipt.dart';
import '../data/repositories/receipt_repository.dart';
import '../data/repositories/repository.dart';
import '../data/repositories/supabase_receipt_repository.dart';
import '../features/dashboard/analytics.dart';

/// Emits the current Supabase [User] whenever auth state changes.
/// Stays null when Supabase is not configured or user is not signed in.
final _authUserProvider = StreamProvider<User?>((ref) {
  if (!Env.hasSupabase) return Stream.value(null);
  try {
    return Supabase.instance.client.auth.onAuthStateChange
        .map((event) => event.session?.user);
  } catch (_) {
    return Stream.value(null);
  }
});

/// Repository + services.
///
/// Watches [_authUserProvider] so it re-evaluates the moment the user signs
/// in and switches transparently from local → Supabase storage.
final repositoryProvider = Provider<ReceiptRepository>((ref) {
  if (Env.hasSupabase) {
    final user = ref.watch(_authUserProvider).valueOrNull;
    if (user != null) {
      try {
        return SupabaseReceiptRepository(Supabase.instance.client);
      } catch (_) {}
    }
  }
  return LocalReceiptRepository();
});

final ocrServiceProvider = Provider<OcrService>((ref) => OcrService());
final extractionServiceProvider =
    Provider<ExtractionService>((ref) => ExtractionService());

/// The user's display currency (from .env, overridable later in settings).
final displayCurrencyProvider =
    StateProvider<String>((ref) => Env.defaultCurrency);

/// ---- Receipts ----

class ReceiptsNotifier extends StateNotifier<AsyncValue<List<Receipt>>> {
  final ReceiptRepository _repo;
  final Ref _ref;
  ReceiptsNotifier(this._repo, this._ref) : super(const AsyncValue.loading()) {
    load();
  }

  Future<void> load() async {
    state = const AsyncValue.loading();
    try {
      state = AsyncValue.data(await _repo.loadReceipts());
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> add(Receipt receipt) async {
    state = AsyncValue.data(await _repo.addReceipt(receipt));
    invalidateMonthlyReview(_ref);
  }

  Future<void> update(Receipt receipt) async {
    state = AsyncValue.data(await _repo.updateReceipt(receipt));
    invalidateMonthlyReview(_ref);
  }

  Future<void> delete(String id) async {
    state = AsyncValue.data(await _repo.deleteReceipt(id));
    invalidateMonthlyReview(_ref);
  }
}

final receiptsProvider =
    StateNotifierProvider<ReceiptsNotifier, AsyncValue<List<Receipt>>>((ref) {
  return ReceiptsNotifier(ref.watch(repositoryProvider), ref);
});

/// ---- Budgets ----

class BudgetsNotifier extends StateNotifier<List<Budget>> {
  final ReceiptRepository _repo;
  final Ref _ref;
  BudgetsNotifier(this._repo, this._ref) : super(const []) {
    load();
  }

  Future<void> load() async {
    state = await _repo.loadBudgets();
  }

  Future<void> save(List<Budget> budgets) async {
    await _repo.saveBudgets(budgets);
    state = budgets;
    invalidateMonthlyReview(_ref);
  }
}

final budgetsProvider =
    StateNotifierProvider<BudgetsNotifier, List<Budget>>((ref) {
  return BudgetsNotifier(ref.watch(repositoryProvider), ref);
});

/// ---- AI Monthly Review ----

/// Bump this to force a re-fetch of the monthly review (e.g. after adding a
/// receipt). Incremented imperatively from notifier actions.
final _reviewInvalidateProvider = StateProvider<int>((ref) => 0);

/// Generates the AI monthly review for the current month.
/// Returns `null` when there are no receipts this month or OpenAI is not
/// configured. Falls back gracefully so the dashboard always works.
final monthlyReviewProvider = FutureProvider.autoDispose<MonthlyReview?>((ref) async {
  ref.watch(_reviewInvalidateProvider);
  final repo = ref.read(repositoryProvider);
  final service = ref.read(extractionServiceProvider);
  final currency = ref.read(displayCurrencyProvider);

  final receipts = await repo.loadReceipts();
  final budgets = await repo.loadBudgets();

  final now = DateTime.now();
  final monthReceipts = receipts
      .where((r) => r.date.year == now.year && r.date.month == now.month)
      .toList();

  if (monthReceipts.isEmpty) return null;

  final analytics = SpendingAnalytics.compute(monthReceipts, now: now);
  final monthLabel = DateFormat.yMMMM().format(now);

  return service.generateMonthlyReview(
    analytics: analytics,
    budgets: budgets,
    currency: currency,
    monthLabel: monthLabel,
  );
});

/// Call this after mutating receipts/budgets to refresh the review.
void invalidateMonthlyReview(Ref ref) {
  ref.read(_reviewInvalidateProvider.notifier).state++;
}
