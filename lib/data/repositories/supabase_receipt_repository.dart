import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/money.dart';
import '../models/budget.dart';
import '../models/category.dart';
import '../models/line_item.dart';
import '../models/receipt.dart';
import 'repository.dart';

/// Supabase-backed store: receipts/line_items/budgets in Postgres, images in
/// the private `receipts` Storage bucket. Activated when SUPABASE_* env vars
/// are set. Requires an authenticated session (anonymous sign-in is fine).
class SupabaseReceiptRepository implements ReceiptRepository {
  final SupabaseClient _db;
  final _uuid = const Uuid();

  SupabaseReceiptRepository(this._db);

  static const _bucket = 'receipts';

  String get _uid => _db.auth.currentUser?.id ?? '';

  @override
  String newId() => _uuid.v4();

  // ---- Receipts ----

  @override
  Future<List<Receipt>> loadReceipts() async {
    final rows = await _db
        .from('receipts')
        .select('*, line_items(*)')
        .order('date', ascending: false);

    final receipts = <Receipt>[];
    for (final row in rows) {
      receipts.add(await _rowToReceipt(row));
    }
    return receipts;
  }

  @override
  Future<List<Receipt>> addReceipt(Receipt receipt) async {
    final imageUrlOrPath = await _maybeUploadImage(receipt);

    await _db.from('receipts').insert({
      'id': receipt.id,
      'user_id': _uid,
      'merchant': receipt.merchant,
      'date': receipt.date.toIso8601String(),
      'total_amount': receipt.total.amount,
      'total_currency': receipt.total.currency,
      'vat_amount': receipt.vat?.amount,
      'vat_currency': receipt.vat?.currency,
      'category': receipt.category.key,
      'image_url': imageUrlOrPath,
      'raw_text': receipt.rawText,
      'notes': receipt.notes,
      'created_at': receipt.createdAt.toIso8601String(),
    });

    await _insertItems(receipt.id, receipt.items);
    return loadReceipts();
  }

  @override
  Future<List<Receipt>> updateReceipt(Receipt receipt) async {
    await _db.from('receipts').update({
      'merchant': receipt.merchant,
      'date': receipt.date.toIso8601String(),
      'total_amount': receipt.total.amount,
      'total_currency': receipt.total.currency,
      'vat_amount': receipt.vat?.amount,
      'vat_currency': receipt.vat?.currency,
      'category': receipt.category.key,
      'notes': receipt.notes,
    }).eq('id', receipt.id);

    await _db.from('line_items').delete().eq('receipt_id', receipt.id);
    await _insertItems(receipt.id, receipt.items);
    return loadReceipts();
  }

  @override
  Future<List<Receipt>> deleteReceipt(String id) async {
    // Best-effort image cleanup.
    try {
      await _db.storage.from(_bucket).remove(['$_uid/$id.jpg']);
    } catch (_) {}
    await _db.from('receipts').delete().eq('id', id);
    return loadReceipts();
  }

  // ---- Budgets ----

  @override
  Future<List<Budget>> loadBudgets() async {
    final rows = await _db.from('budgets').select();
    return (rows as List).map((r) {
      final row = r as Map<String, dynamic>;
      return Budget(
        id: row['id'] as String,
        category: ExpenseCategoryX.fromKey(row['category'] as String?),
        limit: (row['limit_amount'] as num?)?.toDouble() ?? 0,
        currency: row['currency'] as String? ?? 'KES',
      );
    }).toList();
  }

  @override
  Future<void> saveBudgets(List<Budget> budgets) async {
    // Upsert on (user_id, category); remove any that were deleted client-side.
    final keep = budgets.map((b) => b.category.key).toList();
    await _db.from('budgets').upsert(
          budgets
              .map((b) => {
                    'id': b.id,
                    'user_id': _uid,
                    'category': b.category.key,
                    'limit_amount': b.limit,
                    'currency': b.currency,
                  })
              .toList(),
          onConflict: 'user_id,category',
        );
    if (keep.isNotEmpty) {
      await _db
          .from('budgets')
          .delete()
          .eq('user_id', _uid)
          .not('category', 'in', '(${keep.join(',')})');
    }
  }

  // ---- Helpers ----

  Future<void> _insertItems(String receiptId, List<LineItem> items) async {
    if (items.isEmpty) return;
    await _db.from('line_items').insert(items
        .map((it) => {
              'receipt_id': receiptId,
              'user_id': _uid,
              'name': it.name,
              'quantity': it.quantity,
              'unit_price': it.unitPrice,
              'amount': it.amount,
            })
        .toList());
  }

  /// Uploads a local image file to Storage and returns its object path.
  /// If [imagePath] is already a remote URL (or missing), returns it as-is.
  Future<String?> _maybeUploadImage(Receipt receipt) async {
    final path = receipt.imagePath;
    if (path == null || path.isEmpty) return null;
    if (path.startsWith('http')) return path;
    final file = File(path);
    if (!file.existsSync()) return null;

    final objectPath = '$_uid/${receipt.id}.jpg';
    await _db.storage.from(_bucket).upload(
          objectPath,
          file,
          fileOptions: const FileOptions(upsert: true),
        );
    return objectPath;
  }

  Future<Receipt> _rowToReceipt(Map<String, dynamic> row) async {
    final currency = row['total_currency'] as String? ?? 'KES';
    final vatAmount = (row['vat_amount'] as num?)?.toDouble();

    final items = ((row['line_items'] as List?) ?? [])
        .map((e) => LineItem(
              name: (e['name'] ?? '').toString(),
              quantity: (e['quantity'] as num?)?.toDouble() ?? 1,
              unitPrice: (e['unit_price'] as num?)?.toDouble() ?? 0,
              amount: (e['amount'] as num?)?.toDouble() ?? 0,
            ))
        .toList();

    // Convert a stored storage path into a temporary signed URL for display.
    String? displayImage;
    final stored = row['image_url'] as String?;
    if (stored != null && stored.isNotEmpty) {
      if (stored.startsWith('http')) {
        displayImage = stored;
      } else {
        try {
          displayImage =
              await _db.storage.from(_bucket).createSignedUrl(stored, 3600);
        } catch (_) {
          displayImage = null;
        }
      }
    }

    return Receipt(
      id: row['id'] as String,
      businessId: 'default',
      merchant: row['merchant'] as String? ?? 'Unknown',
      date: DateTime.tryParse(row['date'] as String? ?? '') ?? DateTime.now(),
      total: Money((row['total_amount'] as num?)?.toDouble() ?? 0, currency),
      vat: vatAmount == null
          ? null
          : Money(vatAmount, row['vat_currency'] as String? ?? currency),
      category: ExpenseCategoryX.fromKey(row['category'] as String?),
      items: items,
      imagePath: displayImage,
      rawText: row['raw_text'] as String?,
      notes: row['notes'] as String?,
      createdAt:
          DateTime.tryParse(row['created_at'] as String? ?? '') ?? DateTime.now(),
    );
  }
}
