import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_theme.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool _loading = false;
  String? _message;
  bool _messageIsError = true;
  bool _showEmail = false;
  bool _obscure = true;

  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  SupabaseClient get _sb => Supabase.instance.client;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() fn) async {
    setState(() {
      _loading = true;
      _message = null;
    });
    try {
      await fn();
    } on AuthException catch (e) {
      if (mounted) setState(() { _message = e.message; _messageIsError = true; });
    } catch (e) {
      if (mounted) setState(() { _message = e.toString(); _messageIsError = true; });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _oauth(OAuthProvider provider) => _run(
        () => _sb.auth.signInWithOAuth(
          provider,
          redirectTo: 'com.receiptiq://login-callback/',
        ),
      );

  Future<void> _guest() => _run(() async {
        await _sb.auth.signInAnonymously();
        if (mounted) context.go('/dashboard');
      });

  Future<void> _emailAuth() => _run(() async {
        final email = _emailCtrl.text.trim();
        final pass = _passCtrl.text.trim();
        if (email.isEmpty || pass.length < 6) {
          throw Exception('Enter a valid email and a password (6+ characters).');
        }
        try {
          await _sb.auth.signInWithPassword(email: email, password: pass);
          if (mounted) context.go('/dashboard');
        } on AuthException catch (e) {
          if (e.statusCode == '400' ||
              e.message.toLowerCase().contains('invalid')) {
            final res = await _sb.auth.signUp(email: email, password: pass);
            if (res.session != null) {
              if (mounted) context.go('/dashboard');
            } else {
              if (mounted) {
                setState(() {
                  _message = 'Account created! Check your email to confirm, then sign in.';
                  _messageIsError = false;
                });
              }
            }
          } else {
            rethrow;
          }
        }
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 56),
              _buildHero(),
              const SizedBox(height: 48),

              // ── Social sign-in ───────────────────────────────────────────
              _AuthButton(
                onTap: _loading ? null : () => _oauth(OAuthProvider.google),
                leading: _GoogleBadge(),
                label: 'Continue with Google',
                bg: Colors.white,
                fg: const Color(0xFF1A1A1A),
                border: const Color(0xFFCBD5E1),
              ),
              const SizedBox(height: 12),
              _AuthButton(
                onTap: _loading ? null : () => _oauth(OAuthProvider.facebook),
                leading: _FacebookBadge(),
                label: 'Continue with Facebook',
                bg: const Color(0xFF1877F2),
                fg: Colors.white,
              ),
              const SizedBox(height: 24),

              // ── Divider ──────────────────────────────────────────────────
              Row(children: [
                const Expanded(child: Divider()),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Text('or',
                      style: TextStyle(color: Colors.grey[500], fontSize: 13)),
                ),
                const Expanded(child: Divider()),
              ]),
              const SizedBox(height: 24),

              // ── Phone ────────────────────────────────────────────────────
              OutlinedButton.icon(
                onPressed:
                    _loading ? null : () => context.push('/auth/phone'),
                icon: const Icon(Icons.phone_android_outlined),
                label: const Text('Sign in with phone number'),
                style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14)),
              ),
              const SizedBox(height: 12),

              // ── Email toggle ─────────────────────────────────────────────
              OutlinedButton.icon(
                onPressed: _loading
                    ? null
                    : () => setState(() => _showEmail = !_showEmail),
                icon: Icon(
                    _showEmail ? Icons.expand_less : Icons.email_outlined),
                label: Text(
                    _showEmail ? 'Hide email form' : 'Sign in with email'),
                style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14)),
              ),

              // ── Email form (animated) ─────────────────────────────────────
              AnimatedSize(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOut,
                child: _showEmail ? _buildEmailForm() : const SizedBox.shrink(),
              ),

              // ── Feedback banner ──────────────────────────────────────────
              if (_message != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                    color: _messageIsError
                        ? const Color(0xFFFEF2F2)
                        : const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _message!,
                    style: TextStyle(
                      fontSize: 13,
                      color: _messageIsError
                          ? const Color(0xFFDC2626)
                          : const Color(0xFF16A34A),
                    ),
                  ),
                ),
              ],

              if (_loading) ...[
                const SizedBox(height: 24),
                const Center(child: CircularProgressIndicator()),
              ],

              const SizedBox(height: 36),

              // ── Guest ────────────────────────────────────────────────────
              Center(
                child: TextButton(
                  onPressed: _loading ? null : _guest,
                  child: const Text(
                    'Continue as guest (no account needed)',
                    style: TextStyle(
                      color: Color(0xFF94A3B8),
                      decoration: TextDecoration.underline,
                      decorationColor: Color(0xFF94A3B8),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHero() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppTheme.brand.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child:
              const Icon(Icons.receipt_long_rounded, size: 64, color: AppTheme.brand),
        ),
        const SizedBox(height: 20),
        const Text(
          'ReceiptIQ',
          style: TextStyle(
              fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: -0.5),
        ),
        const SizedBox(height: 8),
        const Text(
          'Track smarter, spend better.',
          style: TextStyle(fontSize: 15, color: Color(0xFF64748B)),
        ),
      ],
    );
  }

  Widget _buildEmailForm() {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _emailCtrl,
            decoration: const InputDecoration(
                labelText: 'Email', prefixIcon: Icon(Icons.email_outlined)),
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passCtrl,
            obscureText: _obscure,
            decoration: InputDecoration(
              labelText: 'Password',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                icon: Icon(_obscure
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _emailAuth(),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _loading ? null : _emailAuth,
            child: const Text('Sign in / Create account'),
          ),
        ],
      ),
    );
  }
}

// ── Private widgets ────────────────────────────────────────────────────────────

class _AuthButton extends StatelessWidget {
  final VoidCallback? onTap;
  final Widget leading;
  final String label;
  final Color bg;
  final Color fg;
  final Color? border;

  const _AuthButton({
    required this.onTap,
    required this.leading,
    required this.label,
    required this.bg,
    required this.fg,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: border != null ? Border.all(color: border!) : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              leading,
              const SizedBox(width: 10),
              Text(label,
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600, color: fg)),
            ],
          ),
        ),
      ),
    );
  }
}

class _GoogleBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: const BoxDecoration(
          shape: BoxShape.circle, color: Color(0xFF4285F4)),
      alignment: Alignment.center,
      child: const Text('G',
          style: TextStyle(
              color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
    );
  }
}

class _FacebookBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(4)),
      alignment: Alignment.center,
      child: const Text('f',
          style: TextStyle(
              color: Color(0xFF1877F2),
              fontWeight: FontWeight.w900,
              fontSize: 15,
              height: 1.1)),
    );
  }
}
