import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PhoneOtpScreen extends StatefulWidget {
  const PhoneOtpScreen({super.key});

  @override
  State<PhoneOtpScreen> createState() => _PhoneOtpScreenState();
}

class _PhoneOtpScreenState extends State<PhoneOtpScreen> {
  final _phoneCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  bool _loading = false;
  bool _otpSent = false;
  String? _error;

  SupabaseClient get _sb => Supabase.instance.client;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _otpCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    final phone = _phoneCtrl.text.trim();
    if (phone.isEmpty) return;
    setState(() { _loading = true; _error = null; });
    try {
      await _sb.auth.signInWithOtp(phone: phone);
      if (mounted) setState(() => _otpSent = true);
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _verifyOtp() async {
    final phone = _phoneCtrl.text.trim();
    final token = _otpCtrl.text.trim();
    if (token.length < 4) return;
    setState(() { _loading = true; _error = null; });
    try {
      await _sb.auth.verifyOTP(
        phone: phone,
        token: token,
        type: OtpType.sms,
      );
      if (mounted) context.go('/dashboard');
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
    return Scaffold(
      appBar: AppBar(title: const Text('Phone sign-in')),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!_otpSent) ...[
              const Text(
                'Enter your phone number with country code.',
                style: TextStyle(color: Color(0xFF64748B), height: 1.5),
              ),
              const Text(
                'Example: +254 712 345 678',
                style: TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 13,
                    fontStyle: FontStyle.italic),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _phoneCtrl,
                decoration: const InputDecoration(
                  labelText: 'Phone number',
                  prefixIcon: Icon(Icons.phone),
                  hintText: '+254712345678',
                ),
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _sendOtp(),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _loading ? null : _sendOtp,
                child: _loading
                    ? const _Spinner()
                    : const Text('Send OTP'),
              ),
            ] else ...[
              Text(
                'Enter the code sent to ${_phoneCtrl.text}',
                style: const TextStyle(
                    color: Color(0xFF64748B), height: 1.5),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _otpCtrl,
                decoration: const InputDecoration(
                  labelText: 'Verification code',
                  prefixIcon: Icon(Icons.lock_outline),
                  hintText: '123456',
                ),
                keyboardType: TextInputType.number,
                maxLength: 6,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _verifyOtp(),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _loading ? null : _verifyOtp,
                child: _loading
                    ? const _Spinner()
                    : const Text('Verify & Sign In'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _loading
                    ? null
                    : () => setState(() {
                          _otpSent = false;
                          _error = null;
                          _otpCtrl.clear();
                        }),
                child: const Text('Change number'),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
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
          ],
        ),
      ),
    );
  }
}

class _Spinner extends StatelessWidget {
  const _Spinner();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 18,
      height: 18,
      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
    );
  }
}
