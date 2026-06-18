import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/providers.dart';
import '../../core/money.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/receipt.dart';

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  int _selectedYear = DateTime.now().year;

  @override
  Widget build(BuildContext context) {
    final receiptsAsync = ref.watch(receiptsProvider);
    final currency = ref.watch(displayCurrencyProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('History')),
      body: receiptsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (receipts) {
          final months = _buildMonthSummaries(receipts, currency);
          final years = receipts.map((r) => r.date.year).toSet().toList()
            ..sort((a, b) => b.compareTo(a));

          if (receipts.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.history, size: 48, color: Color(0xFFCBD5E1)),
                    SizedBox(height: 12),
                    Text('No receipts yet.',
                        style: TextStyle(color: Color(0xFF94A3B8))),
                  ],
                ),
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
            children: [
              // ── Year selector + Yearly Review card ───────────────────────
              if (years.isNotEmpty) ...[
                _YearSelector(
                  years: years,
                  selected: _selectedYear,
                  onChanged: (y) => setState(() => _selectedYear = y),
                ),
                const SizedBox(height: 8),
                _YearlyReviewCard(year: _selectedYear),
                const SizedBox(height: 20),
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text('Monthly breakdown',
                      style: TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w700)),
                ),
              ],
              // ── Month cards ───────────────────────────────────────────────
              for (final m in months)
                if (m.year == _selectedYear) _MonthCard(summary: m),
              if (!months.any((m) => m.year == _selectedYear))
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: Text(
                      'No receipts in $_selectedYear.',
                      style: const TextStyle(color: Color(0xFF94A3B8)),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  List<_MonthSummary> _buildMonthSummaries(
      List<Receipt> receipts, String currency) {
    final map = <String, _MonthSummary>{};
    for (final r in receipts) {
      final key =
          '${r.date.year}-${r.date.month.toString().padLeft(2, '0')}';
      map.putIfAbsent(
        key,
        () => _MonthSummary(
          year: r.date.year,
          month: r.date.month,
          key: key,
          currency: currency,
        ),
      );
      map[key]!.totalSpend += r.total.amount;
      map[key]!.receiptCount++;
      map[key]!.topCategory = _pickTopCategory(
          map[key]!.topCategory,
          r.category.label,
          map[key]!.totalSpend);
    }
    final list = map.values.toList()
      ..sort((a, b) {
        final cmp = b.year.compareTo(a.year);
        return cmp != 0 ? cmp : b.month.compareTo(a.month);
      });
    return list;
  }

  String? _pickTopCategory(
      String? current, String newCat, double _) {
    return current ?? newCat;
  }
}

class _MonthSummary {
  final int year;
  final int month;
  final String key;
  final String currency;
  double totalSpend = 0;
  int receiptCount = 0;
  String? topCategory;

  _MonthSummary({
    required this.year,
    required this.month,
    required this.key,
    required this.currency,
  });
}

// ── Year Selector ─────────────────────────────────────────────────────────────

class _YearSelector extends StatelessWidget {
  final List<int> years;
  final int selected;
  final ValueChanged<int> onChanged;
  const _YearSelector(
      {required this.years,
      required this.selected,
      required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: years
            .map((y) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(y.toString()),
                    selected: y == selected,
                    onSelected: (_) => onChanged(y),
                    selectedColor: AppTheme.brand,
                    labelStyle: TextStyle(
                      color:
                          y == selected ? Colors.white : null,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ))
            .toList(),
      ),
    );
  }
}

// ── Yearly Review Card ────────────────────────────────────────────────────────

class _YearlyReviewCard extends ConsumerWidget {
  final int year;
  const _YearlyReviewCard({required this.year});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final receiptsAsync = ref.watch(receiptsProvider);
    final currency = ref.watch(displayCurrencyProvider);

    return receiptsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (receipts) {
        final yearReceipts = receipts.where((r) => r.date.year == year);
        if (yearReceipts.isEmpty) return const SizedBox.shrink();
        final total =
            yearReceipts.fold<double>(0, (s, r) => s + r.total.amount);

        return GestureDetector(
          onTap: () => context.push('/history/year/$year'),
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppTheme.brand, AppTheme.brandDark],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('$year Year in Review',
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 13)),
                      const SizedBox(height: 4),
                      Text(
                        Money(total, currency).format(),
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${yearReceipts.length} receipts',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right,
                    color: Colors.white70, size: 28),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ── Month Card ────────────────────────────────────────────────────────────────

class _MonthCard extends StatelessWidget {
  final _MonthSummary summary;
  const _MonthCard({required this.summary});

  @override
  Widget build(BuildContext context) {
    final label = DateFormat('MMMM yyyy')
        .format(DateTime(summary.year, summary.month));
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        onTap: () => context.push('/history/month/${summary.key}'),
        title: Text(label,
            style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(
            '${summary.receiptCount} receipt${summary.receiptCount == 1 ? '' : 's'}'
            '${summary.topCategory != null ? ' · ${summary.topCategory}' : ''}'),
        trailing: Text(
          Money(summary.totalSpend, summary.currency).format(),
          style: const TextStyle(
              fontWeight: FontWeight.w700, fontSize: 15),
        ),
        leadingAndTrailingTextStyle: null,
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: AppTheme.brand.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Text(
              DateFormat('MMM').format(DateTime(summary.year, summary.month)),
              style: const TextStyle(
                  color: AppTheme.brand,
                  fontWeight: FontWeight.w800,
                  fontSize: 13),
            ),
          ),
        ),
      ),
    );
  }
}
