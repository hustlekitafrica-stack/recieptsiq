import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'budget_model.dart';
import 'budget_repository.dart';

final _budgetRepoProvider = Provider((_) => BudgetRepository());

final budgetProvider =
    AsyncNotifierProvider<BudgetNotifier, Budget?>(BudgetNotifier.new);

class BudgetNotifier extends AsyncNotifier<Budget?> {
  @override
  Future<Budget?> build() => ref.read(_budgetRepoProvider).load();

  Future<void> save(Budget budget) async {
    await ref.read(_budgetRepoProvider).save(budget);
    state = AsyncData(budget);
  }

  Future<void> clear() async {
    await ref.read(_budgetRepoProvider).clear();
    state = const AsyncData(null);
  }
}
