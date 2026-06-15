import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  static const _green = Color(0xFF25D366);

  String? _completePhone;   // E.164 validated number set by IntlPhoneField
  bool    _loading      = false;
  bool    _demoLoading  = false;
  bool    _valid        = false;
  String? _error;

  SupabaseClient get _sb => Supabase.instance.client;

  Future<void> _demoSignIn() async {
    setState(() { _demoLoading = true; _error = null; });
    try {
      await _sb.auth.signInAnonymously();
      if (mounted) context.go('/dashboard');
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _demoLoading = false);
    }
  }

  Future<void> _sendOtp() async {
    if (!_valid || _completePhone == null) {
      setState(() => _error = 'Enter a valid phone number.');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      await _sb.auth.signInWithOtp(
        phone: _completePhone!,
        channel: OtpChannel.whatsapp,
      );
      if (mounted) context.push('/auth/phone', extra: _completePhone!);
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
      backgroundColor: Colors.white,
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
                  const Text(
                    'Sign in or create\nan account',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A),
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    "Enter your phone number to continue. We'll send "
                    "you a one-time verification code on WhatsApp.",
                    style: TextStyle(
                      fontSize: 15,
                      color: Color(0xFF64748B),
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 32),
                  const Text(
                    'Phone number',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 8),
                  IntlPhoneField(
                    initialCountryCode: 'KE',
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _sendOtp(),
                    style: const TextStyle(fontSize: 16, color: Color(0xFF0F172A)),
                    dropdownTextStyle: const TextStyle(
                        fontSize: 16, color: Color(0xFF0F172A)),
                    decoration: InputDecoration(
                      hintText: '700 000 000',
                      hintStyle:
                          const TextStyle(color: Color(0xFFCBD5E1), fontSize: 16),
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
                      errorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                            color: Color(0xFFDC2626), width: 1.5),
                      ),
                      focusedErrorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                            color: Color(0xFFDC2626), width: 2),
                      ),
                    ),
                    onChanged: (phone) {
                      setState(() {
                        _error = null;
                        try {
                          _valid = phone.isValidNumber();
                          _completePhone =
                              _valid ? phone.completeNumber : null;
                        } catch (_) {
                          _valid = false;
                          _completePhone = null;
                        }
                      });
                    },
                    onCountryChanged: (_) =>
                        setState(() { _valid = false; _completePhone = null; }),
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    invalidNumberMessage: 'Invalid phone number for this country',
                    disableLengthCheck: false,
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
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: (_loading || _demoLoading) ? null : _demoSignIn,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: const BorderSide(color: Color(0xFFE2E8F0), width: 1.5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _demoLoading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Color(0xFF64748B)),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: const [
                                Icon(Icons.science_outlined,
                                    size: 18, color: Color(0xFF64748B)),
                                SizedBox(width: 8),
                                Text(
                                  'Try demo (no account needed)',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: Color(0xFF64748B),
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
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

