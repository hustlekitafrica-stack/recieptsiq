import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class OcrException implements Exception {
  final String message;
  OcrException(this.message);
  @override
  String toString() => 'OcrException: $message';
}

/// Reads raw text from a receipt image via the [scan-ocr] Supabase Edge Function.
///
/// Flow:
///   1. Upload image to the private `ocr-temp` Storage bucket.
///   2. Call the Edge Function with the storage path.
///   3. The function downloads the image server-side, calls Google Vision,
///      deletes the temp file, and returns the extracted text.
class OcrService {
  static const _bucket = 'ocr-temp';
  static const _fn     = 'scan-ocr';
  static const _uuid   = Uuid();

  SupabaseClient get _sb => Supabase.instance.client;

  Future<String> readText(File image) async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) throw OcrException('Not signed in — cannot scan.');

    // ── 1. Upload to temp bucket ──────────────────────────────────────────
    final tempPath = '$uid/${_uuid.v4()}.jpg';
    try {
      await _sb.storage.from(_bucket).upload(
        tempPath,
        image,
        fileOptions: const FileOptions(upsert: true),
      );
    } catch (e) {
      throw OcrException('Failed to upload image: $e');
    }

    // ── 2. Invoke Edge Function ───────────────────────────────────────────
    try {
      final res = await _sb.functions.invoke(
        _fn,
        body: {'storage_path': tempPath},
      );
      final data = res.data as Map?;
      if (data?['error'] != null) {
        throw OcrException(data!['error'].toString());
      }
      final text = data?['text'] as String?;
      if (text == null || text.trim().isEmpty) {
        throw OcrException('Could not read any text from this receipt.');
      }
      return text;
    } on FunctionException catch (e) {
      throw OcrException('OCR request failed: ${e.details}');
    } catch (e) {
      if (e is OcrException) rethrow;
      throw OcrException('OCR request failed: $e');
    }
  }
}
