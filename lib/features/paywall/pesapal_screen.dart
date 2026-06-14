import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../data/models/subscription_tier.dart';

/// Pesapal hosted checkout screen.
///
/// Calls `payments/initiate-pesapal` Edge Function to get a hosted checkout
/// URL, then loads it in a WebView. Pesapal posts an IPN to the Edge Function
/// on payment confirmation, which updates [user_subscriptions].
class PesapalScreen extends StatefulWidget {
  final SubscriptionTier tier;
  const PesapalScreen({super.key, required this.tier});

  @override
  State<PesapalScreen> createState() => _PesapalScreenState();
}

class _PesapalScreenState extends State<PesapalScreen> {
  WebViewController? _controller;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initCheckout();
  }

  Future<void> _initCheckout() async {
    try {
      final client = Supabase.instance.client;
      final response = await client.functions.invoke(
        'payments/initiate-pesapal',
        body: jsonEncode({'tier': widget.tier.name}),
      );
      if (response.status != 200) {
        throw Exception(response.data?['error'] ?? 'Failed to create Pesapal order');
      }
      final checkoutUrl = response.data['checkoutUrl'] as String;
      final ctrl = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(NavigationDelegate(
          onPageStarted: (_) => setState(() => _loading = true),
          onPageFinished: (_) => setState(() => _loading = false),
          onNavigationRequest: (req) {
            if (req.url.contains('payment-success') ||
                req.url.contains('pesapal-callback')) {
              context.pop(widget.tier);
              return NavigationDecision.prevent;
            }
            if (req.url.contains('payment-cancelled') ||
                req.url.contains('pesapal-cancel')) {
              context.pop();
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ))
        ..loadRequest(Uri.parse(checkoutUrl));
      setState(() => _controller = ctrl);
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pesapal Checkout'),
        actions: [
          if (_controller != null)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => _controller!.reload(),
            ),
        ],
      ),
      body: Stack(
        children: [
          if (_error != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline,
                        color: Color(0xFFEF4444), size: 48),
                    const SizedBox(height: 12),
                    Text(_error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Color(0xFF64748B))),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () {
                        setState(() {
                          _error = null;
                          _loading = true;
                        });
                        _initCheckout();
                      },
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
          else if (_controller != null)
            WebViewWidget(controller: _controller!),
          if (_loading && _error == null)
            const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}
