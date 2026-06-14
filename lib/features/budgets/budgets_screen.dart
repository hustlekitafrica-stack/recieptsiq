import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/subscription_provider.dart';
import '../../core/money.dart';
import '../../data/models/budget.dart';
import '../../data/models/category.dart';
import '../dashboard/analytics.dart';

class BudgetsScreen extends ConsumerWidget {
  const BudgetsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final budgets = ref.watch(budgetsProvider);
    final receiptsAsync = ref.watch(receiptsProvider);
    final currency = ref.watch(displayCurrencyProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Budgets'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _editBudget(context, ref, currency, null),
          ),
        ],
      ),
      body: receiptsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (receipts) {
          final spent = SpendingAnalytics.compute(receipts).byCategory;
          if (budgets.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('No budgets yet.',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: () =>
                          _editBudget(context, ref, currency, null),
                      icon: const Icon(Icons.add),
                      label: const Text('Add a budget'),
                    ),
                  ],
                ),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
            children: budgets.map((b) {
              final used = spent[b.category] ?? 0;
              final pct = b.limit > 0 ? (used / b.limit).clamp(0.0, 1.0) : 0.0;
              final over = used > b.limit;
              final near = pct >= 0.9;
              final barColor = over
                  ? const Color(0xFFEF4444)
                  : near
                      ? const Color(0xFFF59E0B)
                      : b.category.color;
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(b.category.icon, color: b.category.color),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(b.category.label,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15)),
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, size: 18),
                            onPressed: () => _editBudget(
                                context, ref, currency, b),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: pct,
                          minHeight: 10,
                          backgroundColor: const Color(0xFFEFF1F5),
                          valueColor: AlwaysStoppedAnimation(barColor),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${Money(used, currency).format()} of ${Money(b.limit, b.currency).format()}',
                        style: const TextStyle(color: Color(0xFF64748B)),
                      ),
                      if (near || over)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            over
                                ? 'Over budget by ${Money(used - b.limit, currency).format()}'
                                : 'You have used ${(pct * 100).toStringAsFixed(0)}% of this budget.',
                            style: TextStyle(
                                color: barColor,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }

  Future<void> _editBudget(BuildContext context, WidgetRef ref,
      String currency, Budget? existing) async {
    // Enforce tier budget limit only when adding a new budget.
    if (existing == null) {
      final caps = ref.read(tierCapabilitiesProvider);
      final currentCount = ref.read(budgetsProvider).length;
      if (!caps.isUnlimitedBudgets && currentCount >= caps.maxBudgets) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Budget limit reached ($currentCount / ${caps.maxBudgets}). Upgrade to add more.',
            ),
            action: SnackBarAction(
              label: 'Upgrade',
              onPressed: () => context.push('/paywall'),
            ),
          ),
        );
        return;
      }
    }
    final controller = TextEditingController(
        text: existing == null ? '' : existing.limit.toStringAsFixed(0));
    var category = existing?.category ?? ExpenseCategory.groceries;

    final result = await showDialog<Budget>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(existing == null ? 'Add budget' : 'Edit budget'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<ExpenseCategory>(
                initialValue: category,
                isExpanded: true,
                items: ExpenseCategory.values
                    .map((c) => DropdownMenuItem(
                        value: c,
                        child: Row(children: [
                          Icon(c.icon, size: 18, color: c.color),
                          const SizedBox(width: 8),
                          Text(c.label),
                        ])))
                    .toList(),
                onChanged: existing != null
                    ? null
                    : (v) => setState(() => category = v ?? category),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly
                ],
                decoration:
                    const InputDecoration(labelText: 'Monthly limit'),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final limit = double.tryParse(controller.text.trim()) ?? 0;
                Navigator.pop(
                  ctx,
                  Budget(
                    id: existing?.id ?? ref.read(repositoryProvider).newId(),
                    category: category,
                    limit: limit,
                    currency: existing?.currency ?? currency,
                  ),
                );
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (result == null) return;
    final current = [...ref.read(budgetsProvider)];
    final idx = current.indexWhere((b) => b.category == result.category);
    if (idx >= 0) {
      current[idx] = result;
    } else {
      current.add(result);
    }
    await ref.read(budgetsProvider.notifier).save(current);
  }
}
