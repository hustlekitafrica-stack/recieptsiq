import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/monthly_review.dart';

class MonthlyReviewScreen extends ConsumerStatefulWidget {
  const MonthlyReviewScreen({super.key});

  @override
  ConsumerState<MonthlyReviewScreen> createState() => _MonthlyReviewScreenState();
}

class _MonthlyReviewScreenState extends ConsumerState<MonthlyReviewScreen> {
  bool _refreshing = false;

  Future<void> _refresh() async {
    final now = DateTime.now();
    final month = DateTime(now.year, now.month);
    final cacheKey = '${month.year}_${month.month.toString().padLeft(2, '0')}';
    setState(() => _refreshing = true);
    try {
      await ref.read(repositoryProvider).clearMonthlyReviewCache(cacheKey);
      ref.invalidate(monthlyReviewProvider(month));
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final month = DateTime(now.year, now.month);
    final reviewAsync = ref.watch(monthlyReviewProvider(month));
    final monthLabel = DateFormat.yMMMM().format(now);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Monthly Review'),
        actions: [
          _refreshing
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : IconButton(
                  icon: const Icon(Icons.refresh_rounded),
                  tooltip: 'Regenerate',
                  onPressed: _refresh,
                ),
        ],
      ),
      body: reviewAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _ErrorBody(error: e.toString()),
        data: (review) {
          if (review == null) return const _EmptyBody();
          return _ReviewBody(review: review, monthLabel: monthLabel);
        },
      ),
    );
  }
}

class _ReviewBody extends StatelessWidget {
  final MonthlyReview review;
  final String monthLabel;
  const _ReviewBody({required this.review, required this.monthLabel});

  Color get _toneColor {
    switch (review.tone) {
      case 'positive':
        return AppTheme.accent;
      case 'caution':
        return const Color(0xFFF59E0B);
      default:
        return const Color(0xFF64748B);
    }
  }

  IconData get _toneIcon {
    switch (review.tone) {
      case 'positive':
        return Icons.sentiment_satisfied_outlined;
      case 'caution':
        return Icons.warning_amber_outlined;
      default:
        return Icons.sentiment_neutral_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.fromLTRB(16, 8, 16,
          32 + MediaQuery.of(context).padding.bottom),
      children: [
        // Month label + tone badge
        Row(
          children: [
            Text(monthLabel,
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF94A3B8))),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _toneColor.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(_toneIcon, size: 16, color: _toneColor),
                  const SizedBox(width: 4),
                  Text(
                    review.tone.substring(0, 1).toUpperCase() +
                        review.tone.substring(1),
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _toneColor),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        // Headline
        Text(
          review.headline,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, height: 1.2),
        ),
        const SizedBox(height: 12),
        // Summary
        Text(
          review.summary,
          style: const TextStyle(
              fontSize: 15, height: 1.5, color: Color(0xFF475569)),
        ),
        const SizedBox(height: 24),
        // Insights
        if (review.insights.isNotEmpty) ...[
          _SectionTitle('Insights', Icons.lightbulb_outline, AppTheme.brand),
          const SizedBox(height: 8),
          ...review.insights.map((i) => _BulletCard(text: i, color: AppTheme.brand)),
          const SizedBox(height: 20),
        ],
        // Tips
        if (review.tips.isNotEmpty) ...[
          _SectionTitle('Tips', Icons.auto_fix_high_outlined, AppTheme.accent),
          const SizedBox(height: 8),
          ...review.tips.map((t) => _BulletCard(text: t, color: AppTheme.accent)),
          const SizedBox(height: 20),
        ],
        // Budget alerts
        if (review.budgetAlerts.isNotEmpty) ...[
          _SectionTitle('Budget alerts', Icons.notifications_outlined,
              const Color(0xFFF59E0B)),
          const SizedBox(height: 8),
          ...review.budgetAlerts
              .map((a) => _BulletCard(text: a, color: const Color(0xFFF59E0B))),
        ],
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  final IconData icon;
  final Color color;
  const _SectionTitle(this.text, this.icon, this.color);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Text(text,
            style: TextStyle(
                fontSize: 15, fontWeight: FontWeight.w700, color: color)),
      ],
    );
  }
}

class _BulletCard extends StatelessWidget {
  final String text;
  final Color color;
  const _BulletCard({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.20)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 6),
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: const TextStyle(fontSize: 14, height: 1.4)),
          ),
        ],
      ),
    );
  }
}

class _EmptyBody extends StatelessWidget {
  const _EmptyBody();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.receipt_long_outlined,
                size: 48, color: Color(0xFFCBD5E1)),
            SizedBox(height: 12),
            Text('No receipts this month yet.',
                style: TextStyle(color: Color(0xFF94A3B8))),
          ],
        ),
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  final String error;
  const _ErrorBody({required this.error});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Color(0xFFEF4444)),
            const SizedBox(height: 12),
            const Text('Could not generate review.',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(error,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 13, color: Color(0xFF94A3B8))),
          ],
        ),
      ),
    );
  }
}
