import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/providers.dart';
import '../../core/widgets/guest_nudge_banner.dart';
import '../../data/models/receipt.dart';

class ReceiptsScreen extends ConsumerWidget {
  const ReceiptsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final receiptsAsync = ref.watch(receiptsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Receipts')),
      body: Column(
        children: [
          const GuestNudgeBanner(),
          Expanded(child: receiptsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (receipts) {
          if (receipts.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'No receipts yet.\nTap the scan button to add your first one.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          final groups = _groupByMonth(receipts);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
            children: [
              for (final entry in groups.entries) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text(
                    entry.key,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
                ...entry.value.map((r) => _ReceiptTile(receipt: r)),
              ],
            ],
          );
        },
      )),
        ],
      ),
    );
  }

  Map<String, List<Receipt>> _groupByMonth(List<Receipt> receipts) {
    final map = <String, List<Receipt>>{};
    final fmt = DateFormat('MMMM yyyy');
    for (final r in receipts) {
      map.putIfAbsent(fmt.format(r.date), () => []).add(r);
    }
    return map;
  }
}

class _ReceiptTile extends StatelessWidget {
  final Receipt receipt;
  const _ReceiptTile({required this.receipt});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: () => context.push('/receipt/${receipt.id}'),
        leading: CircleAvatar(
          backgroundColor: receipt.category.color.withValues(alpha: 0.15),
          child: Icon(receipt.category.icon, color: receipt.category.color),
        ),
        title: Text(receipt.merchant,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
            '${receipt.category.label} · ${DateFormat.MMMd().format(receipt.date)}'),
        trailing: Text(receipt.total.format(),
            style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }
}
