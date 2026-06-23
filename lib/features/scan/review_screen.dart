import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/providers.dart';
import '../../app/subscription_provider.dart';
import '../../core/money.dart';
import '../../data/models/category.dart';
import '../../data/models/line_item.dart';
import '../../data/models/receipt.dart';
import '../../data/models/receipt_draft.dart';

class ReviewScreen extends ConsumerStatefulWidget {
  final ReceiptDraft draft;
  const ReviewScreen({super.key, required this.draft});

  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends ConsumerState<ReviewScreen> {
  late final TextEditingController _merchant;
  late final TextEditingController _total;
  late final TextEditingController _vat;
  late DateTime _date;
  late String _currency;
  late List<LineItem> _items;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final d = widget.draft;
    _merchant = TextEditingController(text: d.merchant);
    _total = TextEditingController(
        text: d.total == 0 ? '' : d.total.toStringAsFixed(2));
    _vat = TextEditingController(
        text: (d.vat == null || d.vat == 0) ? '' : d.vat!.toStringAsFixed(2));
    _date = d.date;
    _currency = d.currency;
    _items = List<LineItem>.from(d.items.map((it) => it.copyWith(
          category: it.category ?? Category.other,
        )));
  }

  @override
  void dispose() {
    _merchant.dispose();
    _total.dispose();
    _vat.dispose();
    super.dispose();
  }

  /// Picks the highest-spend item category as the receipt-level category so
  /// analytics and budgets continue to work without user input.
  /// Spend-weighted because each item now carries a specific unique category —
  /// frequency count would be arbitrary when all categories are distinct.
  Category _dominantCategory() {
    if (_items.isEmpty) return Category.other;
    final spend = <String, double>{};
    for (final it in _items) {
      final key = it.category?.key ?? Category.other.key;
      spend[key] = (spend[key] ?? 0) + it.amount;
    }
    final topKey =
        spend.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    return _items
            .firstWhere(
              (i) => (i.category?.key ?? Category.other.key) == topKey,
              orElse: () => _items.first,
            )
            .category ??
        Category.other;
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final repo = ref.read(repositoryProvider);
    final total = double.tryParse(_total.text.trim()) ?? 0;
    final vat = double.tryParse(_vat.text.trim());

    final receipt = Receipt(
      id: repo.newId(),
      businessId: 'default',
      merchant: _merchant.text.trim().isEmpty
          ? 'Unknown merchant'
          : _merchant.text.trim(),
      date: _date,
      total: Money(total, _currency),
      vat: (vat != null && vat > 0) ? Money(vat, _currency) : null,
      category: _dominantCategory(),
      items: _items,
      imagePath: widget.draft.imagePath,
      rawText: widget.draft.rawText,
      createdAt: DateTime.now(),
    );

    try {
      final existing = ref.read(receiptsProvider).valueOrNull ?? [];
      await ref.read(receiptsProvider.notifier).add(receipt);
      if (!mounted) return;

      final caps = ref.read(tierCapabilitiesProvider);
      final insight = caps.postScanInsight
          ? _buildPriceInsight(receipt, existing, _currency)
          : null;
      if (insight != null && mounted) {
        await showModalBottomSheet<void>(
          context: context,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          builder: (_) => _PostScanInsightSheet(
            receipt: receipt,
            insight: insight,
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Receipt saved')),
        );
      }
      if (mounted) context.pushReplacement('/receipts');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ignore: avoid_void_async
  void _saveGuarded() { _save().catchError((_) {}); }

  static String? _buildPriceInsight(
      Receipt newReceipt, List<Receipt> existing, String currency) {
    final prev = existing
        .where((r) =>
            r.merchant.toLowerCase() ==
                newReceipt.merchant.toLowerCase() &&
            r.id != newReceipt.id)
        .toList();

    if (prev.length < 3) return null;

    final avgTotal =
        prev.fold<double>(0, (s, r) => s + r.total.amount) / prev.length;
    final currentTotal = newReceipt.total.amount;

    if (avgTotal <= 0) return null;

    final diff = currentTotal - avgTotal;
    final pct = (diff / avgTotal) * 100;

    if (pct >= 10) {
      return 'You normally spend ${Money(avgTotal, currency).format()} at '
          '${newReceipt.merchant}. This receipt is ${Money(diff.abs(), currency).format()} '
          'above your usual amount.';
    }
    if (pct <= -10) {
      return 'Great deal! This is ${Money(diff.abs(), currency).format()} '
          'below your usual spend at ${newReceipt.merchant}.';
    }
    return null;
  }

  Future<void> _pickItemCategory(int index) async {
    final current = _items[index].category ?? Category.other;
    final allOptions = {current, ...Category.predefined}.toList();

    await showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
              child: Text('Category for "${_items[index].name}"',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 15)),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: allOptions.length,
                itemBuilder: (_, i) {
                  final cat = allOptions[i];
                  final selected = cat == current;
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: cat.color.withValues(alpha: 0.15),
                      child: Icon(cat.icon, color: cat.color, size: 20),
                    ),
                    title: Text(cat.label,
                        style: TextStyle(
                            fontWeight: selected
                                ? FontWeight.w700
                                : FontWeight.normal)),
                    trailing:
                        selected ? const Icon(Icons.check, size: 18) : null,
                    onTap: () {
                      setState(() {
                        _items[index] = _items[index].copyWith(category: cat);
                      });
                      Navigator.of(ctx).pop();
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.draft;
    return Scaffold(
      appBar: AppBar(title: const Text('Review receipt')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
            16, 8, 16, 24 + MediaQuery.of(context).padding.bottom),
        children: [
          if (d.imagePath != null && File(d.imagePath!).existsSync())
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.file(File(d.imagePath!),
                  height: 180, width: double.infinity, fit: BoxFit.cover),
            ),
          const SizedBox(height: 16),
          _label('Merchant'),
          TextField(controller: _merchant),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label('Date'),
                    InkWell(
                      onTap: _pickDate,
                      child: InputDecorator(
                        decoration: const InputDecoration(),
                        child: Text(DateFormat.yMMMd().format(_date)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 110,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label('Currency'),
                    DropdownButtonFormField<String>(
                      initialValue: kSupportedCurrencies.containsKey(_currency)
                          ? _currency
                          : 'KES',
                      isExpanded: true,
                      items: kSupportedCurrencies.keys
                          .map((c) =>
                              DropdownMenuItem(value: c, child: Text(c)))
                          .toList(),
                      onChanged: (v) =>
                          setState(() => _currency = v ?? _currency),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label('Total'),
                    TextField(
                      controller: _total,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label('VAT (optional)'),
                    TextField(
                      controller: _vat,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_items.isNotEmpty) ...[
            const SizedBox(height: 18),
            _label('Items (${_items.length})'),
            const SizedBox(height: 4),
            ..._items.asMap().entries.map((entry) {
              final idx = entry.key;
              final it = entry.value;
              final cat = it.category ?? Category.other;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(it.name,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w500)),
                          const SizedBox(height: 2),
                          Text(
                            '${it.quantity % 1 == 0 ? it.quantity.toInt() : it.quantity}'
                            ' x ${Money(it.unitPrice, _currency).format()}',
                            style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: () => _pickItemCategory(idx),
                      child: Chip(
                        avatar: Icon(cat.icon, size: 14, color: cat.color),
                        label: Text(cat.label,
                            style: TextStyle(
                                fontSize: 11,
                                color: cat.color,
                                fontWeight: FontWeight.w600)),
                        backgroundColor: cat.color.withValues(alpha: 0.1),
                        side: BorderSide(color: cat.color.withValues(alpha: 0.3)),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        materialTapTargetSize:
                            MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 52),
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: _saving
                    ? const Row(
                        key: ValueKey('saving'),
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(width: 10),
                          Text(
                            'Saving…',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ],
                      )
                    : const Row(
                        key: ValueKey('idle'),
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.check, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'Save receipt',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2015),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text,
            style: const TextStyle(
                fontWeight: FontWeight.w600, color: Color(0xFF475569))),
      );
}

class _PostScanInsightSheet extends StatelessWidget {
  final Receipt receipt;
  final String insight;
  const _PostScanInsightSheet(
      {required this.receipt, required this.insight});

  @override
  Widget build(BuildContext context) {
    final isAbove = insight.contains('above your usual');
    final color =
        isAbove ? const Color(0xFFF59E0B) : const Color(0xFF22C55E);
    final icon = isAbove
        ? Icons.trending_up_rounded
        : Icons.thumb_up_outlined;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 30),
            ),
            const SizedBox(height: 14),
            Text(
              'Receipt saved ✓',
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              receipt.merchant,
              style: const TextStyle(
                  color: Color(0xFF64748B), fontSize: 14),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: color.withValues(alpha: 0.25)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.lightbulb_outline,
                      color: color, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      insight,
                      style: TextStyle(
                          fontSize: 14,
                          color: color,
                          fontWeight: FontWeight.w600,
                          height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Got it'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
