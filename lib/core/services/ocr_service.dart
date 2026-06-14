import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import '../config/env.dart';

class OcrException implements Exception {
  final String message;
  OcrException(this.message);
  @override
  String toString() => 'OcrException: $message';
}

/// Reads raw text from a receipt image using the Google Cloud Vision API.
///
/// NOTE: For production, proxy this through a backend/Edge Function so the
/// API key is never shipped in the app binary.
class OcrService {
  final Dio _dio;
  OcrService([Dio? dio]) : _dio = dio ?? Dio();

  static const _endpoint = 'https://vision.googleapis.com/v1/images:annotate';

  Future<String> readText(File image) async {
    if (!Env.hasVision) {
      throw OcrException('Google Vision API key is not configured.');
    }

    final bytes = await image.readAsBytes();
    final base64Image = base64Encode(bytes);

    try {
      final response = await _dio.post(
        _endpoint,
        queryParameters: {'key': Env.googleVisionApiKey},
        data: {
          'requests': [
            {
              'image': {'content': base64Image},
              'features': [
                {'type': 'DOCUMENT_TEXT_DETECTION'}
              ],
              'imageContext': {
                'languageHints': ['en']
              }
            }
          ]
        },
      );

      final responses = response.data['responses'] as List?;
      if (responses == null || responses.isEmpty) {
        throw OcrException('No text detected in the image.');
      }
      final first = responses.first as Map<String, dynamic>;
      if (first['error'] != null) {
        throw OcrException(first['error']['message']?.toString() ??
            'Vision API returned an error.');
      }
      final fullText = first['fullTextAnnotation']?['text'] as String?;
      if (fullText == null || fullText.trim().isEmpty) {
        throw OcrException('Could not read any text from this receipt.');
      }
      return fullText;
    } on DioException catch (e) {
      final msg = e.response?.data is Map
          ? (e.response?.data['error']?['message']?.toString() ?? e.message)
          : e.message;
      throw OcrException('OCR request failed: $msg');
    }
  }
}
