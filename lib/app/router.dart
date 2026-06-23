import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/env.dart';
import '../data/models/receipt_draft.dart';
import '../data/models/subscription_tier.dart';
import '../features/analytics/analytics_screen.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/dashboard/monthly_review_screen.dart';
import '../features/auth/auth_screen.dart';
import '../features/auth/phone_otp_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/paywall/paywall_screen.dart';
import '../features/paywall/pesapal_screen.dart';
import '../features/receipts/receipt_detail_screen.dart';
import '../features/receipts/receipts_screen.dart';
import '../features/history/history_month_detail_screen.dart';
import '../features/history/history_screen.dart';
import '../features/history/yearly_review_screen.dart';
import '../features/scan/review_screen.dart';
import '../features/scan/scan_screen.dart';
import '../features/budgets/budget_screen.dart';
import '../features/export/export_screen.dart';
import '../features/leaks/leaks_screen.dart';
import '../features/search/search_screen.dart';
import '../features/suppliers/suppliers_screen.dart';
import 'app_shell.dart';

final _rootKey = GlobalKey<NavigatorState>();
final _shellKey = GlobalKey<NavigatorState>();

/// Listens to Supabase auth state and notifies [GoRouter] to re-run redirect.
class _AuthNotifier extends ChangeNotifier {
  StreamSubscription<AuthState>? _sub;

  _AuthNotifier() {
    try {
      _sub = Supabase.instance.client.auth.onAuthStateChange
          .listen((_) => notifyListeners());
    } catch (_) {}
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

/// Builds the app router. [onboarded] decides whether the first screen is the
/// dashboard or the first-run onboarding flow.
Page<void> _slidePage(Widget child) => CustomTransitionPage(
  child: child,
  transitionsBuilder: (context, animation, secondaryAnimation, child) {
    final slideIn = CurvedAnimation(parent: animation, curve: Curves.easeInOut);
    final slideOut = CurvedAnimation(parent: secondaryAnimation, curve: Curves.easeInOut);
    return SlideTransition(
      position: Tween(begin: Offset.zero, end: const Offset(-0.3, 0.0)).animate(slideOut),
      child: SlideTransition(
        position: Tween(begin: const Offset(1.0, 0.0), end: Offset.zero).animate(slideIn),
        child: child,
      ),
    );
  },
);

GoRouter createAppRouter({required bool onboarded}) {
  final notifier = Env.hasSupabase ? _AuthNotifier() : null;

  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: onboarded ? '/dashboard' : '/onboarding',
    refreshListenable: notifier,
    redirect: (context, state) {
      if (!Env.hasSupabase) {
        if (state.matchedLocation.startsWith('/auth')) return '/dashboard';
        return null;
      }
      User? user;
      try { user = Supabase.instance.client.auth.currentUser; } catch (_) {}
      final hasSession    = user != null;
      final isAnon        = user?.isAnonymous ?? false;
      final hasRealAccount = hasSession && !isAnon;
      final onAuth        = state.matchedLocation.startsWith('/auth');
      final onOnboarding  = state.matchedLocation == '/onboarding';
      final onPaywall     = state.matchedLocation.startsWith('/paywall');

      // Truly no session (not even anonymous) → force onboarding / sign-in.
      if (!hasSession && !onAuth && !onOnboarding) return '/onboarding';
      // Real (non-anon) account on auth screens → already signed in
      if (hasRealAccount && onAuth) return '/dashboard';
      return null;
    },
    routes: _routes,
  );
}

final _routes = <RouteBase>[
  GoRoute(
    path: '/onboarding',
    parentNavigatorKey: _rootKey,
    builder: (c, s) => const OnboardingScreen(),
  ),
    ShellRoute(
      navigatorKey: _shellKey,
      builder: (context, state, child) => AppShell(child: child),
      routes: [
        GoRoute(
          path: '/dashboard',
          pageBuilder: (c, s) =>
              const NoTransitionPage(child: DashboardScreen()),
        ),
        GoRoute(
          path: '/receipts',
          pageBuilder: (c, s) =>
              const NoTransitionPage(child: ReceiptsScreen()),
        ),
        GoRoute(
          path: '/analytics',
          pageBuilder: (c, s) =>
              const NoTransitionPage(child: AnalyticsScreen()),
        ),
        GoRoute(
          path: '/search',
          pageBuilder: (c, s) => const NoTransitionPage(child: SearchScreen()),
        ),
      ],
    ),
    GoRoute(
      path: '/scan',
      parentNavigatorKey: _rootKey,
      builder: (c, s) => const ScanScreen(),
    ),
    GoRoute(
      path: '/review',
      parentNavigatorKey: _rootKey,
      builder: (c, s) => ReviewScreen(draft: s.extra as ReceiptDraft),
    ),
    GoRoute(
      path: '/receipt/:id',
      parentNavigatorKey: _rootKey,
      builder: (c, s) => ReceiptDetailScreen(receiptId: s.pathParameters['id']!),
    ),
    GoRoute(
      path: '/review/monthly',
      parentNavigatorKey: _rootKey,
      builder: (c, s) => const MonthlyReviewScreen(),
    ),
    GoRoute(
      path: '/paywall',
      parentNavigatorKey: _rootKey,
      builder: (c, s) {
        final defaultTier = s.extra as SubscriptionTier?;
        return PaywallScreen(defaultTier: defaultTier);
      },
    ),
    GoRoute(
      path: '/paywall/pesapal',
      parentNavigatorKey: _rootKey,
      builder: (c, s) {
        final args = s.extra as PaymentArgs;
        return PesapalScreen(tier: args.tier, billingPeriod: args.billingPeriod);
      },
    ),
    GoRoute(
      path: '/auth',
      parentNavigatorKey: _rootKey,
      pageBuilder: (c, s) => _slidePage(const AuthScreen()),
    ),
    GoRoute(
      path: '/auth/phone',
      parentNavigatorKey: _rootKey,
      pageBuilder: (c, s) {
        final args = s.extra as Map<String, dynamic>? ?? {};
        return _slidePage(PhoneOtpScreen(
          email: args['email'] as String? ?? '',
          isUpgrade: args['upgrade'] as bool? ?? false,
        ));
      },
    ),
    GoRoute(
      path: '/history',
      parentNavigatorKey: _rootKey,
      builder: (c, s) => const HistoryScreen(),
    ),
    GoRoute(
      path: '/history/month/:yearMonth',
      parentNavigatorKey: _rootKey,
      builder: (c, s) => HistoryMonthDetailScreen(
          yearMonth: s.pathParameters['yearMonth']!),
    ),
    GoRoute(
      path: '/history/year/:year',
      parentNavigatorKey: _rootKey,
      builder: (c, s) => YearlyReviewScreen(
          year: int.parse(s.pathParameters['year']!)),
    ),
    GoRoute(
      path: '/budget',
      parentNavigatorKey: _rootKey,
      builder: (c, s) => const BudgetScreen(),
    ),
    GoRoute(
      path: '/leaks',
      parentNavigatorKey: _rootKey,
      builder: (c, s) => const LeaksScreen(),
    ),
    GoRoute(
      path: '/suppliers',
      parentNavigatorKey: _rootKey,
      builder: (c, s) => const SuppliersScreen(),
    ),
    GoRoute(
      path: '/export',
      parentNavigatorKey: _rootKey,
      builder: (c, s) => const ExportScreen(),
    ),
];
