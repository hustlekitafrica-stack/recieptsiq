import 'dart:io';

import 'package:cunning_document_scanner/cunning_document_scanner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/providers.dart';
import '../../app/subscription_provider.dart';
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

  // ── Scan limit gate ───────────────────────────────────────────────────────
  bool _checkScanLimit() {
    final canScan = ref.read(canScanProvider);
    if (!canScan) {
      final caps = ref.read(tierCapabilitiesProvider);
      final used = ref.read(scansThisMonthProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Scan limit reached ($used / ${caps.maxScansPerMonth} this month). Upgrade to scan more.',
          ),
          action: SnackBarAction(
            label: 'Upgrade',
            onPressed: () => context.push('/paywall'),
          ),
        ),
      );
      return false;
    }
    return true;
  }

  // ── Document scanner (CamScanner-style) ──────────────────────────────────
  Future<void> _scanDocument() async {
    if (!_checkScanLimit()) return;
    try {
      final pictures = await CunningDocumentScanner.getPictures(
        noOfPages: 1,
        isGalleryImportAllowed: false,
      );
      if (pictures == null || pictures.isEmpty) return;
      await _process(File(pictures.first));
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().toLowerCase();
      final isNativeError = msg.contains('null') ||
          msg.contains('platformexception') ||
          msg.contains('nullpointer');
      if (isNativeError) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Camera scanner unavailable'),
            content: const Text(
              'The document scanner could not start on this device. '
              'You can still scan by picking an image from your gallery.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton.icon(
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Use gallery'),
                onPressed: () {
                  Navigator.pop(ctx);
                  _pickFromGallery();
                },
              ),
            ],
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Scanner error: $e')),
        );
      }
    }
  }

  // ── Gallery fallback ──────────────────────────────────────────────────────
  Future<void> _pickFromGallery() async {
    if (!_checkScanLimit()) return;
    final XFile? file = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
      maxWidth: 2400,
    );
    if (file == null) return;
    await _process(File(file.path));
  }

  // ── Shared processing pipeline ────────────────────────────────────────────
  Future<void> _process(File image) async {
    final currency = ref.read(displayCurrencyProvider);

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

      // Record successful scan against the usage counter.
      await ref.read(usageServiceProvider)?.recordScan();

      if (!mounted) return;
      setState(() => _busy = false);
      context.pushReplacement('/review', extra: draft);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      final msg = e.toString().toLowerCase();
      final noText = msg.contains('no text') || msg.contains('no text detected');
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(noText ? 'Receipt not readable' : 'Scan failed'),
          content: Text(
            noText
                ? 'No text could be read from this image. '
                    'Try retaking with better lighting, or enter the receipt details manually.'
                : 'Something went wrong: $e\n\nYou can try again or enter the details manually.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Try again'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                final draft = ReceiptDraft.empty(currency)
                  ..imagePath = image.path;
                context.pushReplacement('/review', extra: draft);
              },
              child: const Text('Enter manually'),
            ),
          ],
        ),
      );
    }
  }

  void _showMissingKeysDialog(String imagePath, String currency) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cloud scan not available'),
        content: const Text(
          'Scanning requires a Supabase connection. '
          'Add SUPABASE_URL and SUPABASE_ANON_KEY to your .env file, '
          'or enter this receipt manually now.',
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
    final theme = Theme.of(context);

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
          : SafeArea(
              child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 8),
                  // ── Hero illustration ──────────────────────────────────
                  Center(
                    child: Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        color: AppTheme.brand.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(32),
                      ),
                      child: const Icon(Icons.document_scanner_outlined,
                          size: 64, color: AppTheme.brand),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Scan your receipt',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Point the camera at a receipt. Edge detection will auto-crop '
                    'and correct the perspective — just like a desktop scanner.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: const Color(0xFF64748B)),
                  ),
                  const SizedBox(height: 32),
                  // ── Feature chips ──────────────────────────────────────
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: const [
                      _FeatureChip(
                          icon: Icons.crop_free, label: 'Auto edge detect'),
                      _FeatureChip(
                          icon: Icons.flip_camera_android_outlined,
                          label: 'Perspective fix'),
                      _FeatureChip(
                          icon: Icons.auto_fix_high_outlined,
                          label: 'Smart crop'),
                    ],
                  ),
                  const Spacer(),
                  // ── Primary: document scanner ──────────────────────────
                  FilledButton.icon(
                    onPressed: _scanDocument,
                    icon: const Icon(Icons.document_scanner_outlined),
                    label: const Text('Scan document'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // ── Secondary: gallery ─────────────────────────────────
                  OutlinedButton.icon(
                    onPressed: _pickFromGallery,
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Choose from gallery'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            ),
    );
  }
}

class _FeatureChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _FeatureChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.brand.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: AppTheme.brand),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppTheme.brand,
            ),
          ),
        ],
      ),
    );
  }
}
