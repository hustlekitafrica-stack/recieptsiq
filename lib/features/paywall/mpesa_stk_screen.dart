import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/subscription_tier.dart';

/// M-Pesa STK Push checkout screen.
///
/// Flow:
/// 1. User enters their M-Pesa phone number.
/// 2. App calls the Supabase Edge Function `payments/initiate-stk`.
/// 3. Safaricom sends a payment PIN prompt to the user's phone.
/// 4. App polls the Edge Function `payments/check-stk` until confirmed or
///    timed out.
class MpesaStkScreen extends ConsumerStatefulWidget {
  final SubscriptionTier tier;
  const MpesaStkScreen({super.key, required this.tier});

  @override
  ConsumerState<MpesaStkScreen> createState() => _MpesaStkScreenState();
}

class _MpesaStkScreenState extends ConsumerState<MpesaStkScreen> {
  final _phoneController = TextEditingController(text: '254');
  final _formKey = GlobalKey<FormState>();

  _Step _step = _Step.input;
  String _checkoutRequestId = '';
  Timer? _pollTimer;
  int _pollCount = 0;
  static const _maxPolls = 30;

  @override
  void dispose() {
    _pollTimer?.cancel();
    _phoneController.dispose();
    super.dispose();
  }

  String get _tierLabel =>
      widget.tier == SubscriptionTier.pro ? 'Pro' : 'Starter';

  String get _amount =>
      widget.tier == SubscriptionTier.pro ? '1000' : '250';

  Future<void> _initiateStk() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _step = _Step.sending);

    try {
      final phone = _phoneController.text.trim().replaceAll(RegExp(r'\s'), '');
      final client = Supabase.instance.client;
      final response = await client.functions.invoke(
        'payments-initiate-stk',
        body: jsonEncode({
          'phone': phone,
          'tier': widget.tier.name,
          'amount': _amount,
          'currency': 'KES',
        }),
      );

      if (response.status != 200) {
        throw Exception(
            response.data?['error'] ?? 'Failed to initiate M-Pesa payment');
      }

      _checkoutRequestId = response.data['checkoutRequestId'] as String;
      setState(() => _step = _Step.waiting);
      _startPolling();
    } catch (e) {
      if (mounted) {
        setState(() => _step = _Step.input);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  void _startPolling() {
    _pollCount = 0;
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      _pollCount++;
      if (_pollCount > _maxPolls) {
        _pollTimer?.cancel();
        if (mounted) setState(() => _step = _Step.timeout);
        return;
      }
      await _checkStatus();
    });
  }

  Future<void> _checkStatus() async {
    try {
      final client = Supabase.instance.client;
      final response = await client.functions.invoke(
        'payments-check-stk',
        body: jsonEncode({'checkoutRequestId': _checkoutRequestId}),
      );
      if (response.status != 200) return;
      final status = response.data['status'] as String?;
      if (status == 'confirmed') {
        _pollTimer?.cancel();
        if (mounted) {
          setState(() => _step = _Step.success);
          await Future.delayed(const Duration(seconds: 2));
          if (mounted) context.pop(widget.tier);
        }
      } else if (status == 'failed') {
        _pollTimer?.cancel();
        if (mounted) setState(() => _step = _Step.failed);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pay via M-Pesa')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    switch (_step) {
      case _Step.input:
        return _buildInputForm();
      case _Step.sending:
        return _buildStatus(
          icon: Icons.phone_android_outlined,
          title: 'Sending STK Push…',
          subtitle: 'Please wait while we contact Safaricom.',
          loading: true,
        );
      case _Step.waiting:
        return _buildStatus(
          icon: Icons.phone_android_outlined,
          title: 'Check your phone',
          subtitle:
              'An M-Pesa payment prompt has been sent to ${_phoneController.text}.\n\nEnter your M-Pesa PIN to complete the payment.',
          loading: true,
          loadingLabel: 'Waiting for confirmation…',
        );
      case _Step.success:
        return _buildStatus(
          icon: Icons.check_circle_outline,
          iconColor: const Color(0xFF10B981),
          title: 'Payment confirmed!',
          subtitle: 'Welcome to $_tierLabel. Enjoy all your new features.',
          loading: false,
        );
      case _Step.failed:
        return _buildFailure();
      case _Step.timeout:
        return _buildTimeout();
    }
  }

  Widget _buildInputForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFF4CAF50).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              children: [
                const Icon(Icons.phone_android_outlined,
                    color: Color(0xFF4CAF50), size: 40),
                const SizedBox(height: 10),
                Text('Pay KES $_amount for $_tierLabel',
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 18)),
                const SizedBox(height: 4),
                const Text(
                  'You will receive an STK Push on your phone to authorise payment.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          TextFormField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'M-Pesa phone number',
              helperText: 'Format: 254XXXXXXXXX',
              prefixIcon: Icon(Icons.phone),
              border: OutlineInputBorder(),
            ),
            validator: (v) {
              if (v == null || v.isEmpty) return 'Required';
              if (!RegExp(r'^2547\d{8}$').hasMatch(v) &&
                  !RegExp(r'^2541\d{8}$').hasMatch(v)) {
                return 'Enter a valid Kenyan number (254...)';
              }
              return null;
            },
          ),
          const SizedBox(height: 8),
          const Text(
            'By continuing you consent to auto-renewal. Cancel any time from settings.',
            style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
          ),
          const Spacer(),
          FilledButton.icon(
            onPressed: _initiateStk,
            icon: const Icon(Icons.send_outlined),
            label: const Text('Send STK Push'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              backgroundColor: const Color(0xFF4CAF50),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatus({
    required IconData icon,
    Color? iconColor,
    required String title,
    required String subtitle,
    required bool loading,
    String? loadingLabel,
  }) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (loading)
          const CircularProgressIndicator(color: AppTheme.brand)
        else
          Icon(icon, color: iconColor ?? AppTheme.brand, size: 64),
        const SizedBox(height: 20),
        Text(title,
            textAlign: TextAlign.center,
            style:
                const TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
        const SizedBox(height: 10),
        Text(subtitle,
            textAlign: TextAlign.center,
            style:
                const TextStyle(color: Color(0xFF64748B), fontSize: 14, height: 1.5)),
        if (loadingLabel != null) ...[
          const SizedBox(height: 16),
          Text(loadingLabel,
              style:
                  const TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
        ],
      ],
    );
  }

  Widget _buildFailure() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.cancel_outlined, color: Color(0xFFEF4444), size: 64),
        const SizedBox(height: 16),
        const Text('Payment declined',
            textAlign: TextAlign.center,
            style:
                TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
        const SizedBox(height: 8),
        const Text(
            'The M-Pesa payment was not completed. This may happen if you cancelled the prompt or entered an incorrect PIN.',
            textAlign: TextAlign.center,
            style:
                TextStyle(color: Color(0xFF64748B), fontSize: 13, height: 1.5)),
        const SizedBox(height: 28),
        FilledButton(
          onPressed: () => setState(() => _step = _Step.input),
          child: const Text('Try again'),
        ),
        const SizedBox(height: 10),
        OutlinedButton(
          onPressed: () => context.pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }

  Widget _buildTimeout() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.timer_off_outlined,
            color: Color(0xFFF59E0B), size: 64),
        const SizedBox(height: 16),
        const Text('Payment timed out',
            textAlign: TextAlign.center,
            style:
                TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
        const SizedBox(height: 8),
        const Text(
            'We did not receive confirmation within 90 seconds. If money was deducted, please contact support — it will be reversed within 24 hours.',
            textAlign: TextAlign.center,
            style:
                TextStyle(color: Color(0xFF64748B), fontSize: 13, height: 1.5)),
        const SizedBox(height: 28),
        FilledButton(
          onPressed: () => setState(() => _step = _Step.input),
          child: const Text('Try again'),
        ),
        const SizedBox(height: 10),
        OutlinedButton(
          onPressed: () => context.pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

enum _Step { input, sending, waiting, success, failed, timeout }
