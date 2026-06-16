import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PhoneOtpScreen extends StatefulWidget {
  final String email;
  const PhoneOtpScreen({super.key, required this.email});

  @override
  State<PhoneOtpScreen> createState() => _PhoneOtpScreenState();
}

class _PhoneOtpScreenState extends State<PhoneOtpScreen> {
  static const _green  = Color(0xFF25D366);
  static const _digits = 6;
  static const _resend = 60;

  final _ctrl  = TextEditingController();
  final _focus = FocusNode();

  bool    _loading     = false;
  String? _error;
  int     _secondsLeft = _resend;
  Timer?  _timer;

  SupabaseClient get _sb => Supabase.instance.client;
  String get _otp => _ctrl.text;
  bool   get _ready => _otp.length == _digits && !_loading;

  @override
  void initState() {
    super.initState();
    _startCountdown();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  void _startCountdown() {
    _timer?.cancel();
    setState(() => _secondsLeft = _resend);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_secondsLeft == 0) { _timer?.cancel(); return; }
      setState(() => _secondsLeft--);
    });
  }

  Future<void> _resendOtp() async {
    setState(() { _loading = true; _error = null; });
    try {
      await _sb.auth.signInWithOtp(
        email: widget.email,
        shouldCreateUser: true,
      );
      _startCountdown();
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _verify() async {
    if (!_ready) return;
    setState(() { _loading = true; _error = null; });
    try {
      await _sb.auth.verifyOTP(
        email: widget.email,
        token: _otp,
        type: OtpType.email,
      );
      if (mounted) context.go('/dashboard');
    } on AuthException catch (e) {
      if (mounted) {
        _ctrl.clear();
        setState(() { _error = e.message; _loading = false; });
        _focus.requestFocus();
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(),
              const Text(
                'Check your\nemail',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F172A),
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 12),
              Text.rich(
                TextSpan(
                  style: const TextStyle(
                      fontSize: 15, color: Color(0xFF64748B), height: 1.5),
                  children: [
                    const TextSpan(
                        text: "We've sent a 6-digit code to "),
                    TextSpan(
                      text: widget.email,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const TextSpan(
                        text: '. Please enter this code to continue.'),
                  ],
                ),
              ),
              const SizedBox(height: 36),

              // ── OTP boxes ───────────────────────────────────────────────
              _OtpBoxes(
                ctrl: _ctrl,
                focus: _focus,
                digits: _digits,
                onChanged: () {
                  setState(() {});
                  if (_otp.length == _digits) _verify();
                },
              ),

              if (_error != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(_error!,
                      style: const TextStyle(
                          color: Color(0xFFDC2626), fontSize: 13)),
                ),
              ],

              const SizedBox(height: 28),

              // ── Verify button ────────────────────────────────────────────
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _ready ? _verify : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: _green,
                    disabledBackgroundColor: _green.withValues(alpha: 0.4),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2.5))
                      : const Text(
                          'Verify email',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.white),
                        ),
                ),
              ),

              const SizedBox(height: 20),

              // ── Countdown / resend ───────────────────────────────────────
              Center(
                child: _secondsLeft > 0
                    ? Text.rich(
                        TextSpan(
                          text: "Didn't receive a code? Request another in ",
                          style: const TextStyle(
                              fontSize: 13, color: Color(0xFF64748B)),
                          children: [
                            TextSpan(
                              text: '${_secondsLeft}s',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF0F172A)),
                            ),
                          ],
                        ),
                      )
                    : TextButton(
                        onPressed: _loading ? null : _resendOtp,
                        child: const Text('Resend code',
                            style: TextStyle(
                                color: _green,
                                fontWeight: FontWeight.w600)),
                      ),
              ),

              Center(
                child: TextButton(
                  onPressed: () => context.pop(),
                  child: const Text('Back to email',
                      style: TextStyle(
                          color: _green, fontWeight: FontWeight.w600)),
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
    );
  }
}

// ── OTP input: hidden TextField + visual boxes ────────────────────────────────

class _OtpBoxes extends StatelessWidget {
  final TextEditingController ctrl;
  final FocusNode focus;
  final int digits;
  final VoidCallback onChanged;

  const _OtpBoxes({
    required this.ctrl,
    required this.focus,
    required this.digits,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Visual boxes (non-interactive)
        IgnorePointer(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(digits, (i) {
              final filled = i < ctrl.text.length;
              final active = i == ctrl.text.length;
              return _OtpBox(
                digit: filled ? ctrl.text[i] : '',
                active: active,
              );
            }),
          ),
        ),
        // Invisible TextField that captures all input
        Positioned.fill(
          child: Opacity(
            opacity: 0.0,
            child: TextField(
              controller: ctrl,
              focusNode: focus,
              maxLength: digits,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(counterText: ''),
              onChanged: (_) => onChanged(),
            ),
          ),
        ),
      ],
    );
  }
}

class _OtpBox extends StatelessWidget {
  final String digit;
  final bool   active;
  const _OtpBox({required this.digit, required this.active});

  static const _green = Color(0xFF25D366);

  @override
  Widget build(BuildContext context) {
    final hasFill = digit.isNotEmpty;
    return Container(
      width: 48,
      height: 56,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: (hasFill || active) ? _green : const Color(0xFFE2E8F0),
          width: (hasFill || active) ? 2.5 : 1.5,
        ),
      ),
      child: Text(
        digit,
        style: const TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: Color(0xFF0F172A),
        ),
      ),
    );
  }
}
