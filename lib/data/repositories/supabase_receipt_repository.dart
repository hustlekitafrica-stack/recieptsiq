import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/money.dart';
import '../models/category.dart';
import '../models/line_item.dart';
import '../models/monthly_review.dart';
import '../models/receipt.dart';
import '../models/yearly_review.dart';
import 'repository.dart';

/// Supabase-backed store: receipts/line_items in Postgres, images in
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

  // ---- Review cache (stored in SharedPreferences regardless of backend) ----

  @override
  Future<MonthlyReview?> loadMonthlyReviewCache(String yearMonth) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('review_cache_${_uid}_$yearMonth');
    if (raw == null) return null;
    try {
      return MonthlyReview.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> saveMonthlyReviewCache(
      String yearMonth, MonthlyReview review) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'review_cache_${_uid}_$yearMonth', jsonEncode(review.toJson()));
  }

  @override
  Future<void> clearMonthlyReviewCache(String yearMonth) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('review_cache_${_uid}_$yearMonth');
  }

  @override
  Future<YearlyReview?> loadYearlyReviewCache(int year) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('yearly_cache_${_uid}_$year');
    if (raw == null) return null;
    try {
      return YearlyReview.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> saveYearlyReviewCache(int year, YearlyReview review) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('yearly_cache_${_uid}_$year', jsonEncode(review.toJson()));
  }

  // ---- Guest Data Migration ----

  /// Migrates all receipts and storage images from an anonymous guest user
  /// to a real authenticated user. Called when a guest signs in to an existing account.
  Future<void> migrateGuestData(String oldUserId, String newUserId) async {
    // 1. Update all receipts from old user ID to new user ID
    final receipts = await _db
        .from('receipts')
        .select('id')
        .eq('user_id', oldUserId);

    for (final receipt in receipts) {
      final receiptId = receipt['id'] as String;
      await _db
          .from('receipts')
          .update({'user_id': newUserId})
          .eq('id', receiptId);
      
      await _db
          .from('line_items')
          .update({'user_id': newUserId})
          .eq('receipt_id', receiptId);
    }

    // 2. Transfer storage images from old folder to new folder
    try {
      final oldPrefix = '$oldUserId/';
      final newPrefix = '$newUserId/';
      
      // List all files in the old user's folder
      final files = await _db.storage.from(_bucket).list(path: oldPrefix);
      
      for (final file in files) {
        if (file.name.isEmpty) continue;
        final oldPath = '$oldPrefix${file.name}';
        final newPath = '$newPrefix${file.name}';
        
        try {
          // Download the file from old location
          final fileData = await _db.storage.from(_bucket).download(oldPath);
          
          // Convert bytes to temporary file
          final tempDir = await getTemporaryDirectory();
          final tempFile = File('${tempDir.path}/${file.name}');
          await tempFile.writeAsBytes(fileData);
          
          // Upload to new location
          await _db.storage.from(_bucket).upload(
                newPath,
                tempFile,
                fileOptions: const FileOptions(upsert: true),
              );
          
          // Delete temporary file
          await tempFile.delete();
          
          // Delete from old location
          await _db.storage.from(_bucket).remove([oldPath]);
        } catch (e) {
          // Log but continue with other files if one fails
          print('Failed to migrate storage file $oldPath: $e');
        }
      }
    } catch (e) {
      print('Failed to list or migrate storage files: $e');
    }

    // 3. Clear guest-specific SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('usage_guest_scans');
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
              'category': it.category?.key ?? 'other',
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
              category: Category.fromKey(e['category'] as String?),
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
      category: Category.fromKey(row['category'] as String?),
      items: items,
      imagePath: displayImage,
      rawText: row['raw_text'] as String?,
      notes: row['notes'] as String?,
      createdAt:
          DateTime.tryParse(row['created_at'] as String? ?? '') ?? DateTime.now(),
    );
  }
}
