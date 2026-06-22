import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  static const _green = Color(0xFF25D366);

  final _emailCtrl = TextEditingController();
  bool    _loading = false;
  String? _error;

  SupabaseClient get _sb => Supabase.instance.client;

  /// True when the current Supabase session is an anonymous guest.
  /// In this case we upgrade in-place rather than creating a new account.
  bool get _isUpgrade {
    try {
      return _sb.auth.currentUser?.isAnonymous == true;
    } catch (_) {
      return false;
    }
  }

  bool get _valid {
    final e = _emailCtrl.text.trim();
    return e.contains('@') && e.contains('.');
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    final email = _emailCtrl.text.trim();
    if (!_valid) {
      setState(() => _error = 'Enter a valid email address.');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      if (_isUpgrade) {
        // Upgrade anonymous session in-place — same user ID is preserved.
        await _sb.auth.updateUser(UserAttributes(email: email));
      } else {
        await _sb.auth.signInWithOtp(email: email, shouldCreateUser: true);
      }
      if (mounted) {
        context.push('/auth/phone', extra: {'email': email, 'upgrade': _isUpgrade});
      }
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isUpgrade = _isUpgrade;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.close, color: Color(0xFF64748B)),
            onPressed: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/dashboard');
              }
            },
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: MediaQuery.of(context).size.height -
                  MediaQuery.of(context).padding.top -
                  MediaQuery.of(context).padding.bottom,
            ),
            child: IntrinsicHeight(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Spacer(),
                  Text(
                    isUpgrade
                        ? 'Create your\naccount'
                        : 'Sign in or create\nan account',
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A),
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    isUpgrade
                        ? "Save your receipts permanently and unlock the "
                            "full dashboard. We'll send a one-time code to verify your email."
                        : "Enter your email address to continue. We'll send "
                            "you a one-time verification code.",
                    style: const TextStyle(
                      fontSize: 15,
                      color: Color(0xFF64748B),
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 32),
                  const Text(
                    'Email address',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.done,
                    autocorrect: false,
                    onSubmitted: (_) => _sendOtp(),
                    onChanged: (_) => setState(() => _error = null),
                    style: const TextStyle(fontSize: 16, color: Color(0xFF0F172A)),
                    decoration: InputDecoration(
                      hintText: 'you@example.com',
                      hintStyle:
                          const TextStyle(color: Color(0xFFCBD5E1), fontSize: 16),
                      prefixIcon: const Icon(Icons.email_outlined,
                          color: Color(0xFF94A3B8)),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 16),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: _green, width: 2),
                      ),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _error!,
                        style: const TextStyle(
                            color: Color(0xFFDC2626), fontSize: 13),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: (_loading || !_valid) ? null : _sendOtp,
                      style: FilledButton.styleFrom(
                        backgroundColor: _green,
                        disabledBackgroundColor: _green.withValues(alpha: 0.5),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _loading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2.5),
                            )
                          : const Text(
                              'Send verification code',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ),
                  const Spacer(),
                  const Divider(color: Color(0xFFE2E8F0)),
                  const SizedBox(height: 16),
                  Center(
                    child: Text.rich(
                      TextSpan(
                        text: 'By continuing, you agree with our ',
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFF94A3B8)),
                        children: const [
                          TextSpan(
                            text: 'Terms & conditions',
                            style: TextStyle(
                              color: _green,
                              decoration: TextDecoration.underline,
                              decorationColor: _green,
                            ),
                          ),
                          TextSpan(text: ' and '),
                          TextSpan(
                            text: 'Privacy statement',
                            style: TextStyle(
                              color: _green,
                              decoration: TextDecoration.underline,
                              decorationColor: _green,
                            ),
                          ),
                        ],
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

