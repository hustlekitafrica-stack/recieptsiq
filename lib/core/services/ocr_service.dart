import 'dart:convert';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

class OcrException implements Exception {
  final String message;
  OcrException(this.message);
  @override
  String toString() => 'OcrException: $message';
}

/// Reads raw text from a receipt image by sending the image bytes directly
/// to the [scan-ocr] Edge Function as base64.
///
/// No storage bucket required — the image never needs to be uploaded/downloaded.
class OcrService {
  static const _fn = 'scan-ocr';

  SupabaseClient get _sb => Supabase.instance.client;

  Future<String> readText(File image) async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) throw OcrException('Not signed in — cannot scan.');

    final bytes = await image.readAsBytes();
    final base64Image = base64Encode(bytes);

    try {
      final res = await _sb.functions.invoke(
        _fn,
        body: {'image_base64': base64Image},
      );
      final data = res.data as Map?;
      if (data?['error'] != null) {
        throw OcrException(data!['error'].toString());
      }
      final text = data?['text'] as String?;
      if (text == null || text.trim().isEmpty) {
        throw OcrException(
          'No text could be read from this image. '
          'Make sure the receipt is flat, well-lit, and fully in frame.',
        );
      }
      return text;
    } on OcrException {
      rethrow;
    } on FunctionException catch (e) {
      throw OcrException('OCR request failed: ${e.details}');
    } catch (e) {
      throw OcrException('OCR request failed: $e');
    }
  }
}
