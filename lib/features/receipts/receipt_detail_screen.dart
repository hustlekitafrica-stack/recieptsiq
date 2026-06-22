import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/providers.dart';
import '../../core/money.dart';
import '../../core/widgets/receipt_image.dart';
import '../../data/models/receipt.dart';

class ReceiptDetailScreen extends ConsumerWidget {
  final String receiptId;
  const ReceiptDetailScreen({super.key, required this.receiptId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final receiptsAsync = ref.watch(receiptsProvider);
    final receipt = receiptsAsync.maybeWhen(
      data: (list) {
        for (final r in list) {
          if (r.id == receiptId) return r;
        }
        return null;
      },
      orElse: () => null,
    );

    if (receipt == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Receipt not found.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(receipt.merchant),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _confirmDelete(context, ref, receipt),
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 24 + MediaQuery.of(context).padding.bottom),
        children: [
          if (receipt.imagePath != null && receipt.imagePath!.isNotEmpty)
            ReceiptImage(source: receipt.imagePath),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _row('Merchant', receipt.merchant),
                  _row('Date', DateFormat.yMMMMd().format(receipt.date)),
                  _row('Total', receipt.total.format()),
                  if (receipt.vat != null)
                    _row('VAT', receipt.vat!.format()),
                ],
              ),
            ),
          ),
          if (receipt.items.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text('Items',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Card(
              child: Column(
                children: receipt.items.map((it) {
                  final qty = it.quantity % 1 == 0
                      ? it.quantity.toInt().toString()
                      : it.quantity.toString();
                  return ListTile(
                    title: Text(it.name),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('$qty x ${Money(it.unitPrice, receipt.currency).format()}'),
                        if (it.category != null) ...[
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: it.category!.color.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(it.category!.icon,
                                    size: 11, color: it.category!.color),
                                const SizedBox(width: 4),
                                Text(it.category!.label,
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: it.category!.color,
                                        fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                    trailing:
                        Text(Money(it.amount, receipt.currency).format()),
                  );
                }).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: const TextStyle(color: Color(0xFF64748B))),
            Flexible(
              child: Text(value,
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );

  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, Receipt receipt) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete receipt?'),
        content: Text('Remove the ${receipt.merchant} receipt?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(receiptsProvider.notifier).delete(receipt.id);
      if (context.mounted) context.pop();
    }
  }
}
