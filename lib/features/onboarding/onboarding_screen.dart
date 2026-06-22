import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/env.dart';
import '../../core/theme/app_theme.dart';

/// Shared-preferences key marking that the user finished onboarding.
const kOnboardedKey = 'onboarded_v1';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  bool _loading = false;

  Future<void> _startAsGuest() async {
    setState(() => _loading = true);
    try {
      if (Env.hasSupabase) {
        await Supabase.instance.client.auth
            .signInAnonymously()
            .timeout(const Duration(seconds: 10));
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(kOnboardedKey, true);
      if (!mounted) return;
      context.go('/scan');
    } catch (_) {
      // Network unavailable — still let them in; router allows unauthenticated
      // users through to /onboarding so they won't be looped.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(kOnboardedKey, true);
      if (!mounted) return;
      context.go('/scan');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _signIn() => context.push('/auth');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            children: [
              const Spacer(flex: 2),
              // ── Brand icon ────────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: AppTheme.brand.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.document_scanner_outlined,
                    size: 72, color: AppTheme.brand),
              ),
              const SizedBox(height: 32),
              // ── Headline ──────────────────────────────────────────────────
              const Text(
                'Know where your\nmoney goes',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F172A),
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Scan any receipt. AI reads and categorises every item, '
                'tracks your spending, and spots money leaks — for free.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 15, height: 1.55, color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 32),
              // ── Feature pills ─────────────────────────────────────────────
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: const [
                  _Pill(Icons.camera_alt_outlined, 'Scan receipts'),
                  _Pill(Icons.auto_awesome_outlined, 'AI categorisation'),
                  _Pill(Icons.insights_outlined, 'Spending insights'),
                  _Pill(Icons.lock_open_outlined, 'No signup needed'),
                ],
              ),
              const Spacer(flex: 3),
              // ── Primary CTA ───────────────────────────────────────────────
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _loading ? null : _startAsGuest,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(54),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: _loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2.5))
                      : const Icon(Icons.camera_alt_outlined),
                  label: const Text('Scan my first receipt — free',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(height: 12),
              // ── Secondary CTA ─────────────────────────────────────────────
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: _loading ? null : _signIn,
                  child: const Text(
                    'I already have an account',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF64748B)),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '2 free scans · No credit card · No spam',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final IconData icon;
  final String label;
  const _Pill(this.icon, this.label);

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
          Icon(icon, size: 14, color: AppTheme.brand),
          const SizedBox(width: 5),
          Text(label,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.brand)),
        ],
      ),
    );
  }
}
