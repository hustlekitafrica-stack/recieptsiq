import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/subscription_provider.dart';
import '../../core/config/subscription_config.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/subscription_tier.dart';

class PaywallScreen extends ConsumerStatefulWidget {
  const PaywallScreen({super.key});

  @override
  ConsumerState<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends ConsumerState<PaywallScreen> {
  SubscriptionTier _selected = SubscriptionTier.starter;
  BillingPeriod _billingPeriod = BillingPeriod.monthly;
  bool _busy = false;

  Future<void> _purchase() async {
    setState(() => _busy = true);
    try {
      final result = await context.push<SubscriptionTier>(
        '/paywall/pesapal',
        extra: PaymentArgs(tier: _selected, billingPeriod: _billingPeriod),
      );
      if (result != null && mounted) {
        ref.read(subscriptionTierProvider.notifier).setTier(result);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Welcome to ${result.name.toUpperCase()}! 🎉')),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Purchase failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    setState(() => _busy = true);
    try {
      final service = ref.read(subscriptionServiceProvider);
      final tier = await service.restore();
      if (!mounted) return;
      ref.read(subscriptionTierProvider.notifier).setTier(tier);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tier == SubscriptionTier.free
                ? 'No active subscription found.'
                : 'Subscription restored!',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Restore failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentTier = ref.watch(subscriptionTierProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Choose your plan'),
        actions: [
          TextButton(
            onPressed: _busy ? null : _restore,
            child: const Text('Restore'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        child: Column(
          children: [
            _PaywallHero(),
            const SizedBox(height: 20),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(14),
              ),
              padding: const EdgeInsets.all(4),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _billingPeriod = BillingPeriod.monthly),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: _billingPeriod == BillingPeriod.monthly ? Colors.white : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: _billingPeriod == BillingPeriod.monthly
                              ? [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 4, offset: const Offset(0, 2))]
                              : [],
                        ),
                        child: const Text('Monthly', textAlign: TextAlign.center,
                            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _billingPeriod = BillingPeriod.yearly),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: _billingPeriod == BillingPeriod.yearly ? Colors.white : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: _billingPeriod == BillingPeriod.yearly
                              ? [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 4, offset: const Offset(0, 2))]
                              : [],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text('Yearly', textAlign: TextAlign.center,
                                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF10B981),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text('Save 17%',
                                  style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _TierCard(
              tier: SubscriptionTier.free,
              isSelected: _selected == SubscriptionTier.free,
              isCurrent: currentTier == SubscriptionTier.free,
              billingPeriod: _billingPeriod,
              onTap: () => setState(() => _selected = SubscriptionTier.free),
            ),
            const SizedBox(height: 12),
            _TierCard(
              tier: SubscriptionTier.starter,
              isSelected: _selected == SubscriptionTier.starter,
              isCurrent: currentTier == SubscriptionTier.starter,
              billingPeriod: _billingPeriod,
              onTap: () => setState(() => _selected = SubscriptionTier.starter),
            ),
            const SizedBox(height: 12),
            _TierCard(
              tier: SubscriptionTier.pro,
              isSelected: _selected == SubscriptionTier.pro,
              isCurrent: currentTier == SubscriptionTier.pro,
              billingPeriod: _billingPeriod,
              onTap: () => setState(() => _selected = SubscriptionTier.pro),
            ),
            const SizedBox(height: 24),
            _FeatureTable(),
            const SizedBox(height: 8),
            const Text(
              'Cancel anytime. Prices shown in USD — local currency accepted via mobile money.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_selected == SubscriptionTier.free)
                FilledButton(
                  onPressed: () => context.pop(),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 52),
                    backgroundColor: const Color(0xFF64748B),
                  ),
                  child: const Text(
                    'Continue with Free',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                )
              else if (currentTier == SubscriptionTier.free ||
                  (currentTier == SubscriptionTier.starter &&
                      _selected == SubscriptionTier.pro))
                FilledButton(
                  onPressed: _busy ? null : _purchase,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 52),
                  ),
                  child: _busy
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : Text(
                          _selected == SubscriptionTier.starter
                              ? (_billingPeriod == BillingPeriod.yearly
                                  ? 'Get Starter — \$19.99 / year'
                                  : 'Get Starter — \$1.99 / month')
                              : (_billingPeriod == BillingPeriod.yearly
                                  ? 'Get Pro — \$79.99 / year'
                                  : 'Get Pro — \$7.99 / month'),
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700),
                        ),
                )
              else
                FilledButton(
                  onPressed: null,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 52),
                    disabledBackgroundColor:
                        AppTheme.brand.withValues(alpha: 0.15),
                  ),
                  child: Text(
                    'Current plan: ${currentTier.name.toUpperCase()}',
                    style: const TextStyle(color: AppTheme.brand),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Hero ──────────────────────────────────────────────────────────────────────

class _PaywallHero extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppTheme.brand, AppTheme.brandDark],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
          ),
          child: const Icon(Icons.auto_awesome, color: Colors.white, size: 36),
        ),
        const SizedBox(height: 14),
        const Text(
          'Unlock the full power of ReceiptIQ',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        const Text(
          'AI receipt scanning, spending analytics, and monthly financial reviews — available across Africa via M-Pesa, MTN MoMo, Airtel, and cards.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: Color(0xFF64748B), height: 1.4),
        ),
      ],
    );
  }
}

// ── Tier card ─────────────────────────────────────────────────────────────────

class _TierCard extends StatelessWidget {
  final SubscriptionTier tier;
  final bool isSelected;
  final bool isCurrent;
  final BillingPeriod billingPeriod;
  final VoidCallback onTap;

  const _TierCard({
    required this.tier,
    required this.isSelected,
    required this.isCurrent,
    required this.billingPeriod,
    required this.onTap,
  });

  Widget _badge(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
        child: Text(text,
            style: const TextStyle(
                color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
      );

  @override
  Widget build(BuildContext context) {
    final caps = SubscriptionConfig.capsFor(tier);
    final isFree = tier == SubscriptionTier.free;
    final isPro = tier == SubscriptionTier.pro;
    final isYearly = billingPeriod == BillingPeriod.yearly;
    final price = isFree
        ? 'Free'
        : (isYearly ? (isPro ? '\$79.99' : '\$19.99') : (isPro ? '\$7.99' : '\$1.99'));
    final periodLabel = isFree ? null : (isYearly ? '/ year' : '/ month');
    final borderColor = isSelected ? AppTheme.brand : const Color(0xFFE2E8F0);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          border: Border.all(color: borderColor, width: isSelected ? 2 : 1),
          borderRadius: BorderRadius.circular(18),
          color: isSelected
              ? AppTheme.brand.withValues(alpha: 0.04)
              : Colors.white,
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected ? AppTheme.brand : const Color(0xFFCBD5E1),
                    width: 2,
                  ),
                  color: isSelected ? AppTheme.brand : Colors.white,
                ),
                child: isSelected
                    ? const Icon(Icons.check, color: Colors.white, size: 14)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          caps.displayName,
                          style: const TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 16),
                        ),
                        if (isPro) ...[
                          const SizedBox(width: 8),
                          _badge('Best value', AppTheme.brand),
                        ],
                        if (!isFree && isYearly) ...[
                          const SizedBox(width: 8),
                          _badge('2 months free', const Color(0xFF10B981)),
                        ],
                        if (isCurrent) ...[
                          const SizedBox(width: 8),
                          _badge('Current', const Color(0xFF64748B)),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      caps.isUnlimitedScans
                          ? 'Unlimited scans'
                          : '${caps.maxScansPerMonth} scans / month',
                      style: const TextStyle(
                          color: Color(0xFF64748B), fontSize: 12),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    price,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 18),
                  ),
                  if (periodLabel != null)
                    Text(
                      periodLabel,
                      style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Feature comparison table ──────────────────────────────────────────────────

class _FeatureTable extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final rows = [
      _FeatureRow('Receipt scans / month', '5', '50', 'Unlimited'),
      _FeatureRow('Analytics history', '30 days', '6 months', 'All time'),
      _FeatureRow('Receipt history', '30 days', '6 months', 'All time'),
      _FeatureRow('AI Monthly Review', null, '✓', '✓'),
      _FeatureRow('Full AI Insights', null, '✓', '✓'),
      _FeatureRow('CSV Export', null, null, '✓'),
      _FeatureRow('Support', 'Community', 'Email', 'Priority'),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Compare plans',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
            const SizedBox(height: 12),
            Row(
              children: const [
                Expanded(flex: 3, child: SizedBox()),
                Expanded(
                  child: Text('Free',
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                ),
                Expanded(
                  child: Text('Starter',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          color: AppTheme.brand)),
                ),
                Expanded(
                  child: Text('Pro',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          color: AppTheme.brand)),
                ),
              ],
            ),
            const Divider(height: 16),
            ...rows.map((r) => r.build()),
          ],
        ),
      ),
    );
  }
}

class _FeatureRow {
  final String label;
  final String? free;
  final String? starter;
  final String? pro;
  const _FeatureRow(this.label, this.free, this.starter, this.pro);

  Widget build() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(label,
                style:
                    const TextStyle(fontSize: 12, color: Color(0xFF475569))),
          ),
          Expanded(child: _cell(free)),
          Expanded(child: _cell(starter, highlight: true)),
          Expanded(child: _cell(pro, highlight: true)),
        ],
      ),
    );
  }

  Widget _cell(String? text, {bool highlight = false}) {
    if (text == null) {
      return const Icon(Icons.remove, size: 14, color: Color(0xFFCBD5E1));
    }
    return Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: highlight ? AppTheme.brand : const Color(0xFF475569),
      ),
    );
  }
}
