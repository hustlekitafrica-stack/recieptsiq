import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/subscription_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/subscription_tier.dart';

/// Wraps [child] and, when the user's tier is below [requiredTier], shows a
/// locked overlay that nudges them to the paywall.
class UpgradeGate extends ConsumerWidget {
  final SubscriptionTier requiredTier;
  final Widget child;
  final String? featureName;

  const UpgradeGate({
    super.key,
    required this.requiredTier,
    required this.child,
    this.featureName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tier = ref.watch(subscriptionTierProvider);
    if (_meetsRequirement(tier)) return child;
    return _LockedOverlay(requiredTier: requiredTier, featureName: featureName);
  }

  bool _meetsRequirement(SubscriptionTier userTier) {
    return userTier.index >= requiredTier.index;
  }
}

class _LockedOverlay extends StatelessWidget {
  final SubscriptionTier requiredTier;
  final String? featureName;
  const _LockedOverlay({required this.requiredTier, this.featureName});

  @override
  Widget build(BuildContext context) {
    final tierName = requiredTier == SubscriptionTier.starter ? 'Starter' : 'Pro';
    final feature = featureName ?? 'This feature';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.brand.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.lock_outline, color: AppTheme.brand, size: 28),
            ),
            const SizedBox(height: 14),
            Text(
              '$feature requires $tierName',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
            const SizedBox(height: 6),
            Text(
              'Upgrade your plan to unlock this and more AI-powered features.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => context.push('/paywall'),
              icon: const Icon(Icons.rocket_launch_outlined, size: 18),
              label: Text('Upgrade to $tierName'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 44),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
