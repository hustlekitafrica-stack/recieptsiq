import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
    // If SharedPreferences are still loading, silently block — don't show the
    // sheet yet because we don't know the real count.
    if (ref.read(usageServiceProvider) == null) return false;
    final canScan = ref.read(canScanProvider);
    if (!canScan) {
      _showLimitReachedSheet();
      return false;
    }
    return true;
  }

  void _showLimitReachedSheet() {
    User? user;
    try { user = Supabase.instance.client.auth.currentUser; } catch (_) {}
    final isAnon = user == null || user.isAnonymous;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AppTheme.brand.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.document_scanner_outlined,
                    color: AppTheme.brand, size: 32),
              ),
              const SizedBox(height: 16),
              const Text(
                'Free scans used up',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              Text(
                isAnon
                    ? "You've used your 2 free scans. Upgrade to a plan "
                        'to get more scans and keep your receipts forever.'
                    : "You've used all your free scans this month. "
                        'Upgrade your plan to scan more receipts.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Color(0xFF64748B), fontSize: 14, height: 1.4),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    context.push('/paywall');
                  },
                  icon: const Icon(
                    Icons.rocket_launch_outlined,
                    size: 18,
                  ),
                  label: const Text('View plans'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Maybe later'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Native camera capture ─────────────────────────────────────────────────
  Future<void> _scanDocument() async {
    if (!_checkScanLimit()) return;
    final XFile? file = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 90,
      maxWidth: 2400,
      preferredCameraDevice: CameraDevice.rear,
    );
    if (file == null) return;
    await _process(File(file.path));
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

      // Record successful scan against the appropriate counter.
      final usage = ref.read(usageServiceProvider);
      User? _u;
      try { _u = Supabase.instance.client.auth.currentUser; } catch (_) {}
      if (_u == null || _u.isAnonymous) {
        await usage?.recordGuestScan();
      } else {
        await usage?.recordScan();
      }
      ref.invalidate(canScanProvider);
      ref.invalidate(scansThisMonthProvider);

      if (!mounted) return;
      setState(() => _busy = false);
      context.pushReplacement('/review', extra: draft);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      final msg = e.toString().toLowerCase();
      final noText = msg.contains('no text') || msg.contains('could not read');
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(noText ? 'Receipt not readable' : 'Scan failed'),
          content: Text(
            noText
                ? 'No text could be read from this image. '
                    'Ensure the receipt is flat, well-lit, and fully in frame, then try again.'
                : 'Something went wrong: $e\n\nPlease try again.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Try again'),
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

  Widget _buildLimitReachedBody(bool isAnon) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppTheme.brand.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.document_scanner_outlined,
                    color: AppTheme.brand, size: 40),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Free scans used up',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            Text(
              isAnon
                  ? "You've used your 2 free scans. Upgrade to a plan "
                      'to get more scans and keep your receipts forever.'
                  : "You've used all your free scans this month. "
                      'Upgrade your plan to scan more receipts.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Color(0xFF64748B), fontSize: 15, height: 1.5),
            ),
            const Spacer(),
            FilledButton.icon(
              onPressed: () => context.push('/paywall'),
              icon: const Icon(
                Icons.rocket_launch_outlined,
                size: 18,
              ),
              label: const Text('View plans'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => context.pop(),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              child: const Text('Go back'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final usageLoaded = ref.watch(usageServiceProvider) != null;
    final canScan = ref.watch(canScanProvider);
    final isBlocked = usageLoaded && !canScan;
    User? user;
    try { user = Supabase.instance.client.auth.currentUser; } catch (_) {}
    final isAnon = user == null || user.isAnonymous;

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
          : isBlocked
              ? _buildLimitReachedBody(isAnon)
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
                    'Point your camera at a receipt and take a photo. '
                    'AI will read and extract all the details automatically.',
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
                          icon: Icons.camera_alt_outlined, label: 'Native camera'),
                      _FeatureChip(
                          icon: Icons.auto_awesome_outlined,
                          label: 'AI-powered reading'),
                      _FeatureChip(
                          icon: Icons.receipt_long_outlined,
                          label: 'Auto-extraction'),
                    ],
                  ),
                  const SizedBox(height: 24),
                  // ── Scan countdown ───────────────────────────────────────
                  const _ScanCountdown(),
                  const SizedBox(height: 24),
                  const Spacer(),
                  // ── Primary: document scanner ──────────────────────────
                  FilledButton.icon(
                    onPressed: _scanDocument,
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: const Text('Take photo'),
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

class _ScanCountdown extends ConsumerWidget {
  const _ScanCountdown();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usageLoaded = ref.watch(usageServiceProvider) != null;
    final canScan = ref.watch(canScanProvider);
    final tier = ref.watch(subscriptionTierProvider);
    final caps = ref.watch(tierCapabilitiesProvider);
    
    User? user;
    try { user = Supabase.instance.client.auth.currentUser; } catch (_) {}
    final isAnon = user == null || user.isAnonymous;

    // Show loading state while SharedPreferences loads
    if (!usageLoaded) {
      return const Text(
        'Loading...',
        style: TextStyle(
          fontSize: 13,
          color: Color(0xFF94A3B8),
        ),
        textAlign: TextAlign.center,
      );
    }

    // Guest (anonymous) - lifetime counter
    if (isAnon) {
      final guestScansUsed = ref.watch(guestScansUsedProvider);
      final remaining = SubscriptionConfig.guestMaxScans - guestScansUsed;
      
      if (remaining <= 0) {
        return const Text(
          'You have exhausted your free scans',
          style: TextStyle(
            fontSize: 13,
            color: Color(0xFF94A3B8),
          ),
          textAlign: TextAlign.center,
        );
      }
      
      return Text(
        '$guestScansUsed/${SubscriptionConfig.guestMaxScans} scans used',
        style: const TextStyle(
          fontSize: 13,
          color: Color(0xFF94A3B8),
        ),
        textAlign: TextAlign.center,
      );
    }

    // Registered users - monthly counter
    if (tier == SubscriptionTier.pro) {
      return const Text(
        'Unlimited scans',
        style: TextStyle(
          fontSize: 13,
          color: Color(0xFF94A3B8),
        ),
        textAlign: TextAlign.center,
      );
    }

    final scansThisMonth = ref.watch(scansThisMonthProvider);
    final maxScans = caps.maxScansPerMonth;
    final remaining = maxScans - scansThisMonth;

    if (remaining <= 0) {
      return const Text(
        'You have exhausted your free scans',
        style: TextStyle(
          fontSize: 13,
          color: Color(0xFF94A3B8),
        ),
        textAlign: TextAlign.center,
      );
    }

    return Text(
      '$scansThisMonth/$maxScans scans this month',
      style: const TextStyle(
        fontSize: 13,
        color: Color(0xFF94A3B8),
      ),
      textAlign: TextAlign.center,
    );
  }
}
