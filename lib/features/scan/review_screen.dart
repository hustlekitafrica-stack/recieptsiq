import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/providers.dart';
import '../../core/money.dart';
import '../../data/models/category.dart';
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
  late ExpenseCategory _category;
  late String _currency;

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
    _category = d.category;
    _currency = d.currency;
  }

  @override
  void dispose() {
    _merchant.dispose();
    _total.dispose();
    _vat.dispose();
    super.dispose();
  }

  Future<void> _save() async {
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
      category: _category,
      items: widget.draft.items,
      imagePath: widget.draft.imagePath,
      rawText: widget.draft.rawText,
      createdAt: DateTime.now(),
    );

    await ref.read(receiptsProvider.notifier).add(receipt);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Receipt saved')),
    );
    context.go('/receipts');
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
                        FilteringTextInputFormatter.allow(
                            RegExp(r'[0-9.]'))
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
                        FilteringTextInputFormatter.allow(
                            RegExp(r'[0-9.]'))
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _label('Category'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: ExpenseCategory.values.map((c) {
              final selected = c == _category;
              return ChoiceChip(
                selected: selected,
                onSelected: (_) => setState(() => _category = c),
                avatar: Icon(c.icon,
                    size: 18,
                    color: selected ? Colors.white : c.color),
                label: Text(c.label),
                selectedColor: c.color,
                labelStyle: TextStyle(
                    color: selected ? Colors.white : const Color(0xFF334155),
                    fontWeight: FontWeight.w600),
              );
            }).toList(),
          ),
          if (d.items.isNotEmpty) ...[
            const SizedBox(height: 18),
            _label('Items (${d.items.length})'),
            const SizedBox(height: 4),
            ...d.items.map((it) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(it.name),
                  trailing: Text(
                    '${it.quantity % 1 == 0 ? it.quantity.toInt() : it.quantity} x '
                    '${Money(it.unitPrice, _currency).format()}',
                  ),
                )),
          ],
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.check),
              label: const Text('Save receipt'),
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
