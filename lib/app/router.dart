import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../data/models/receipt_draft.dart';
import '../features/budgets/budgets_screen.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/dashboard/monthly_review_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/receipts/receipt_detail_screen.dart';
import '../features/receipts/receipts_screen.dart';
import '../features/scan/review_screen.dart';
import '../features/scan/scan_screen.dart';
import '../features/search/search_screen.dart';
import 'app_shell.dart';

final _rootKey = GlobalKey<NavigatorState>();
final _shellKey = GlobalKey<NavigatorState>();

/// Builds the app router. [onboarded] decides whether the first screen is the
/// dashboard or the first-run onboarding flow.
GoRouter createAppRouter({required bool onboarded}) => GoRouter(
      navigatorKey: _rootKey,
      initialLocation: onboarded ? '/dashboard' : '/onboarding',
      routes: _routes,
    );

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
];
