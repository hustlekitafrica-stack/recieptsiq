import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/providers.dart';
import '../../core/config/env.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/receipt_draft.dart';

class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> {
  final _picker = ImagePicker();
  bool _busy = false;
  String _status = '';

  Future<void> _capture(ImageSource source) async {
    final XFile? file = await _picker.pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 2000,
    );
    if (file == null) return;
    await _process(File(file.path));
  }

  Future<void> _process(File image) async {
    final currency = ref.read(displayCurrencyProvider);

    // If keys are missing, allow a manual draft so the flow is never blocked.
    if (!Env.canScanForReal) {
      _showMissingKeysDialog(image.path, currency);
      return;
    }

    setState(() {
      _busy = true;
      _status = 'Reading text from receipt…';
    });

    try {
      final ocr = ref.read(ocrServiceProvider);
      final extractor = ref.read(extractionServiceProvider);

      final text = await ocr.readText(image);
      setState(() => _status = 'Understanding the receipt…');
      final draft = await extractor.extract(text, fallbackCurrency: currency);
      draft.imagePath = image.path;

      if (!mounted) return;
      setState(() => _busy = false);
      context.pushReplacement('/review', extra: draft);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  void _showMissingKeysDialog(String imagePath, String currency) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('AI keys not set'),
        content: const Text(
          'Add your Google Vision and OpenAI keys to the .env file to scan '
          'automatically. You can still enter this receipt manually now.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              final draft = ReceiptDraft.empty(currency)..imagePath = imagePath;
              context.pushReplacement('/review', extra: draft);
            },
            child: const Text('Enter manually'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan receipt')),
      body: _busy
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(_status),
                ],
              ),
            )
          : Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      color: AppTheme.brand.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: const Icon(Icons.receipt_long,
                        size: 72, color: AppTheme.brand),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Scan any receipt in seconds',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Take a photo or pick one from your gallery. The AI reads '
                    'the merchant, total, VAT, items and category for you.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFF64748B)),
                  ),
                  const Spacer(),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => _capture(ImageSource.camera),
                      icon: const Icon(Icons.camera_alt_outlined),
                      label: const Text('Take a photo'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () => _capture(ImageSource.gallery),
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('Choose from gallery'),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
    );
  }
}
