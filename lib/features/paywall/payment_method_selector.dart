import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/subscription_provider.dart';
import '../../core/config/subscription_config.dart';
import '../../core/services/payment_routing_service.dart';
import '../../data/models/subscription_tier.dart';

/// Bottom sheet that lists available payment methods for the selected [tier]
/// and routes to the appropriate checkout flow.
class PaymentMethodSelector extends ConsumerWidget {
  final SubscriptionTier tier;
  const PaymentMethodSelector({super.key, required this.tier});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final caps = SubscriptionConfig.capsFor(tier);
    final methods = PaymentRoutingService.methodsForCurrentLocale();

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFE2E8F0),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Pay for ${caps.displayName}',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
          ),
          const SizedBox(height: 4),
          const Text(
            'Choose your preferred payment method',
            style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
          ),
          const SizedBox(height: 20),
          ...methods.map((m) => _MethodTile(
                method: m,
                tier: tier,
                onSelected: (result) => Navigator.of(context).pop(result),
              )),
        ],
      ),
    );
  }
}

class _MethodTile extends ConsumerWidget {
  final PaymentMethod method;
  final SubscriptionTier tier;
  final ValueChanged<SubscriptionTier> onSelected;

  const _MethodTile({
    required this.method,
    required this.tier,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: method.color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(method.icon, color: method.color, size: 22),
        ),
        title: Text(method.name,
            style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(method.subtitle,
            style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
        trailing: const Icon(Icons.chevron_right, color: Color(0xFF94A3B8)),
        onTap: () => _handleTap(context, ref),
      ),
    );
  }

  Future<void> _handleTap(BuildContext context, WidgetRef ref) async {
    switch (method.type) {
      case PaymentMethodType.playStore:
        await _handlePlayStore(context, ref);
        break;
      case PaymentMethodType.mpesa:
        final result = await context.push<SubscriptionTier>(
          '/paywall/mpesa',
          extra: tier,
        );
        if (result != null) onSelected(result);
        break;
      case PaymentMethodType.pesapal:
        final result = await context.push<SubscriptionTier>(
          '/paywall/pesapal',
          extra: tier,
        );
        if (result != null) onSelected(result);
        break;
    }
  }

  Future<void> _handlePlayStore(BuildContext context, WidgetRef ref) async {
    try {
      final service = ref.read(subscriptionServiceProvider);
      final productId = tier == SubscriptionTier.pro
          ? SubscriptionConfig.rcProMonthly
          : SubscriptionConfig.rcStarterMonthly;
      final result = await service.purchase(productId);
      onSelected(result);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Play Store: $e')),
        );
      }
    }
  }
}
