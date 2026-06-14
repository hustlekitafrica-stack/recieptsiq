import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/providers.dart';
import '../../data/models/category.dart';
import '../../data/models/receipt.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final receiptsAsync = ref.watch(receiptsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Search')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Search merchant, item, category…',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
            ),
          ),
          Expanded(
            child: receiptsAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (receipts) {
                final results = _query.isEmpty
                    ? <Receipt>[]
                    : receipts.where((r) => _matches(r, _query)).toList();

                if (_query.isEmpty) {
                  return const Center(
                    child: Text('Type to search your receipts.',
                        style: TextStyle(color: Color(0xFF94A3B8))),
                  );
                }
                if (results.isEmpty) {
                  return const Center(child: Text('No matches found.'));
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                  itemCount: results.length,
                  itemBuilder: (c, i) {
                    final r = results[i];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        onTap: () => context.push('/receipt/${r.id}'),
                        leading: CircleAvatar(
                          backgroundColor:
                              r.category.color.withValues(alpha: 0.15),
                          child: Icon(r.category.icon,
                              color: r.category.color),
                        ),
                        title: Text(r.merchant,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600)),
                        subtitle: Text(
                            '${r.category.label} · ${DateFormat.yMMMd().format(r.date)}'),
                        trailing: Text(r.total.format(),
                            style: const TextStyle(
                                fontWeight: FontWeight.w700)),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  bool _matches(Receipt r, String q) {
    if (r.merchant.toLowerCase().contains(q)) return true;
    if (r.category.label.toLowerCase().contains(q)) return true;
    if (r.items.any((it) => it.name.toLowerCase().contains(q))) return true;
    if (r.total.amount.toStringAsFixed(0).contains(q)) return true;
    return false;
  }
}
