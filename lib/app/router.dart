import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/env.dart';
import '../data/models/receipt_draft.dart';
import '../data/models/subscription_tier.dart';
import '../features/budgets/budgets_screen.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/dashboard/monthly_review_screen.dart';
import '../features/auth/auth_screen.dart';
import '../features/auth/phone_otp_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/paywall/mpesa_stk_screen.dart';
import '../features/paywall/paywall_screen.dart';
import '../features/paywall/pesapal_screen.dart';
import '../features/receipts/receipt_detail_screen.dart';
import '../features/receipts/receipts_screen.dart';
import '../features/scan/review_screen.dart';
import '../features/scan/scan_screen.dart';
import '../features/search/search_screen.dart';
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
      final user = Supabase.instance.client.auth.currentUser;
      final loggedIn = user != null;
      final onAuth = state.matchedLocation.startsWith('/auth');
      final onOnboarding = state.matchedLocation == '/onboarding';
      if (!loggedIn && !onAuth && !onOnboarding) return '/auth';
      if (loggedIn && onAuth) return '/dashboard';
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
          path: '/budgets',
          pageBuilder: (c, s) =>
              const NoTransitionPage(child: BudgetsScreen()),
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
      builder: (c, s) => const PaywallScreen(),
    ),
    GoRoute(
      path: '/paywall/mpesa',
      parentNavigatorKey: _rootKey,
      builder: (c, s) => MpesaStkScreen(tier: s.extra as SubscriptionTier),
    ),
    GoRoute(
      path: '/paywall/pesapal',
      parentNavigatorKey: _rootKey,
      builder: (c, s) => PesapalScreen(tier: s.extra as SubscriptionTier),
    ),
    GoRoute(
      path: '/auth',
      parentNavigatorKey: _rootKey,
      builder: (c, s) => const AuthScreen(),
    ),
    GoRoute(
      path: '/auth/phone',
      parentNavigatorKey: _rootKey,
      builder: (c, s) => const PhoneOtpScreen(),
    ),
];
