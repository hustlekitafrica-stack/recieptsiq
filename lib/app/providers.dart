import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/env.dart';
import '../core/services/extraction_service.dart';
import '../core/services/ocr_service.dart';
import '../data/models/monthly_review.dart';
import '../data/models/receipt.dart';
import '../data/models/yearly_review.dart';
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

// ── Selected dashboard month ───────────────────────────────────────────────

/// The month currently shown on the dashboard. Defaults to the current month.
final selectedDashboardMonthProvider = StateProvider<DateTime>(
  (ref) => DateTime(DateTime.now().year, DateTime.now().month),
);

/// ---- AI Monthly Review ----

/// Bump this to force a re-fetch of the monthly review (e.g. after adding a
/// receipt). Incremented imperatively from notifier actions.
final _reviewInvalidateProvider = StateProvider<int>((ref) => 0);

/// Generates the AI monthly review for the given [month].
/// Checks the local cache first; calls the AI only on a miss, then caches.
/// Returns `null` when there are no receipts that month or AI is not configured.
final monthlyReviewProvider =
    FutureProvider.autoDispose.family<MonthlyReview?, DateTime>((ref, month) async {
  ref.watch(_reviewInvalidateProvider);
  final repo = ref.watch(repositoryProvider);
  final service = ref.read(extractionServiceProvider);
  final currency = ref.read(displayCurrencyProvider);

  final cacheKey =
      '${month.year}_${month.month.toString().padLeft(2, '0')}';

  final cached = await repo.loadMonthlyReviewCache(cacheKey);
  if (cached != null) return cached;

  final receipts = await repo.loadReceipts();

  final monthReceipts = receipts
      .where((r) => r.date.year == month.year && r.date.month == month.month)
      .toList();

  if (monthReceipts.isEmpty) return null;

  final analytics = SpendingAnalytics.compute(monthReceipts, now: month);
  final monthLabel = DateFormat.yMMMM().format(month);

  final review = await service.generateMonthlyReview(
    analytics: analytics,
    currency: currency,
    monthLabel: monthLabel,
  );

  if (review != null) {
    await repo.saveMonthlyReviewCache(cacheKey, review);
  }
  return review;
});

/// Call this after mutating receipts/budgets to refresh the review.
void invalidateMonthlyReview(Ref ref) {
  ref.read(_reviewInvalidateProvider.notifier).state++;
}

// ── Yearly Review ─────────────────────────────────────────────────────────

/// Generates the AI yearly review for the given [year].
/// Cache-first: stored in SharedPreferences, generated on first view.
final yearlyReviewProvider =
    FutureProvider.autoDispose.family<YearlyReview?, int>((ref, year) async {
  final repo = ref.watch(repositoryProvider);
  final service = ref.read(extractionServiceProvider);
  final currency = ref.read(displayCurrencyProvider);

  final cached = await repo.loadYearlyReviewCache(year);
  if (cached != null) return cached;

  final receipts = await repo.loadReceipts();
  final analytics = YearlyAnalytics.compute(receipts, year);

  if (analytics.receiptCount == 0) return null;

  final review = await service.generateYearlyReview(
    analytics: analytics,
    currency: currency,
  );

  if (review != null) {
    await repo.saveYearlyReviewCache(year, review);
    return review;
  }

  return YearlyReview(
    year: year,
    totalSpend: analytics.totalSpend,
    monthlyTotals: analytics.monthlyTotals,
    byCategory: analytics.byCategory,
    topMerchants: analytics.topMerchants,
    bestMonth: analytics.bestMonth,
    worstMonth: analytics.worstMonth,
    receiptCount: analytics.receiptCount,
    yearOverYearChange: analytics.yearOverYearChange,
    headline: '${analytics.year} in review',
    summary: '',
    savingsOpportunities: [],
  );
});
