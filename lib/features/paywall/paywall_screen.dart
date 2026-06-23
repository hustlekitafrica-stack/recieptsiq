import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/subscription_provider.dart';
import '../../core/config/subscription_config.dart';
import '../../core/services/notification_service.dart';
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
    // Anonymous users must create an account before paying.
    User? _user;
    try { _user = Supabase.instance.client.auth.currentUser; } catch (_) {}
    if (_user == null || _user.isAnonymous) {
      context.push('/auth');
      return;
    }
    setState(() => _busy = true);
    try {
      final result = await context.push<SubscriptionTier>(
        '/paywall/pesapal',
        extra: PaymentArgs(tier: _selected, billingPeriod: _billingPeriod),
      );
      if (result != null && mounted) {
        ref.read(subscriptionTierProvider.notifier).setTier(result);
        await NotificationService.updateTier(result);
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

  @override
  Widget build(BuildContext context) {
    final currentTier = ref.watch(subscriptionTierProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Choose your plan'),
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
  static const _free   = _TierStyle(Color(0xFF64748B), Color(0xFFF1F5F9));
  static const _start  = _TierStyle(AppTheme.brand,    Color(0xFFEEF2FF));
  static const _pro    = _TierStyle(Colors.white,      AppTheme.brand);

  @override
  Widget build(BuildContext context) {
    // Compact values — all ≤ 5 chars so they never wrap at flex:1 column width.
    final rows = [
      _FR('Receipt scans / month', '10',    '50',    '∞'),
      _FR('History',               '90 d',  '1 yr',  '∞'),
      _FR('Business Health Score', 'Basic', 'Full',  'Full'),
      _FR('AI Monthly Review',     null,    'check', 'check'),
      _FR('AI Assistant',          null,    '30/mo', '∞'),
      _FR('Supplier Intelligence', null,    'check', 'check'),
      _FR('Money Leak Detector',   '1',     'All',   'All'),
      _FR('CSV Export',            null,    'check', 'check'),
      _FR('PDF Export',            null,    null,    'check'),
      _FR('AI Yearly Review',      null,    null,    'check'),
      _FR('Support',               'Forum', 'Email', 'VIP'),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Compare plans',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
            const SizedBox(height: 14),
            // ── Tier header pills ────────────────────────────────────────────
            Row(
              children: [
                const Expanded(flex: 3, child: SizedBox()),
                Expanded(child: _tierPill('Free',    _free)),
                const SizedBox(width: 4),
                Expanded(child: _tierPill('Starter', _start)),
                const SizedBox(width: 4),
                Expanded(child: _tierPill('Pro',     _pro)),
              ],
            ),
            const SizedBox(height: 10),
            // ── Feature rows ─────────────────────────────────────────────────
            ...rows.indexed.map(
              (e) => _FeatureRow(
                row: e.$2,
                shaded: e.$1.isEven,
                freeStyle: _free,
                startStyle: _start,
                proStyle: _pro,
              ),
            ),
            // ── Legend ───────────────────────────────────────────────────────
            const SizedBox(height: 8),
            const Text(
              '∞ = Unlimited',
              style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8)),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _tierPill(String label, _TierStyle style) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 5),
      decoration: BoxDecoration(
        color: style.bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: style.fg,
        ),
      ),
    );
  }
}

// Lightweight data holder
class _FR {
  final String label;
  final String? free, starter, pro;
  const _FR(this.label, this.free, this.starter, this.pro);
}

class _TierStyle {
  final Color fg, bg;
  const _TierStyle(this.fg, this.bg);
}

class _FeatureRow extends StatelessWidget {
  final _FR row;
  final bool shaded;
  final _TierStyle freeStyle, startStyle, proStyle;

  const _FeatureRow({
    required this.row,
    required this.shaded,
    required this.freeStyle,
    required this.startStyle,
    required this.proStyle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: shaded ? const Color(0xFFF8FAFC) : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
      ),
      padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 2),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              row.label,
              style: const TextStyle(fontSize: 12, color: Color(0xFF475569)),
            ),
          ),
          Expanded(child: _cell(row.free,    freeStyle,  solid: false)),
          const SizedBox(width: 4),
          Expanded(child: _cell(row.starter, startStyle, solid: false)),
          const SizedBox(width: 4),
          Expanded(child: _cell(row.pro,     proStyle,   solid: true)),
        ],
      ),
    );
  }

  Widget _cell(String? value, _TierStyle style, {required bool solid}) {
    if (value == null) {
      return const Center(
        child: Icon(Icons.remove, size: 13, color: Color(0xFFCBD5E1)),
      );
    }
    if (value == 'check') {
      return Center(
        child: Icon(Icons.check_circle_outline,
            size: 15, color: solid ? AppTheme.brand : AppTheme.brand),
      );
    }
    // Text chip
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: style.bg,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          value,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: style.fg,
          ),
        ),
      ),
    );
  }
}
