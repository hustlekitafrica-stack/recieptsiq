import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/router.dart';
import 'core/config/env.dart';
import 'core/services/subscription_service.dart';
import 'core/theme/app_theme.dart';
import 'features/onboarding/onboarding_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Load runtime config. Missing .env should not crash the app.
  try {
    await dotenv.load(fileName: '.env');
  } catch (_) {
    // No .env bundled; features needing keys will show a friendly message.
  }

  // First-run check decides whether we open onboarding or the dashboard.
  final prefs = await SharedPreferences.getInstance();
  final onboarded = prefs.getBool(kOnboardedKey) ?? false;

  // Initialise Supabase only when configured.
  if (Env.hasSupabase) {
    try {
      await Supabase.initialize(
        url: Env.supabaseUrl,
        publishableKey: Env.supabaseAnonKey,
      );
    } catch (_) {
      // Ignore init errors in MVP; local store still works.
    }
  }

  // Initialise RevenueCat only when the key is present.
  String? supabaseUserId;
  if (Env.hasSupabase) {
    try {
      supabaseUserId = Supabase.instance.client.auth.currentUser?.id;
    } catch (_) {}
  }
  if (Env.hasRevenueCat) {
    try {
      await SubscriptionService().configure(userId: supabaseUserId);
    } catch (_) {
      // Non-fatal: offline / misconfigured key.
    }
  }

  runApp(ProviderScope(
    child: ReceiptIQApp(
      router: createAppRouter(onboarded: onboarded),
    ),
  ));
}

class ReceiptIQApp extends StatelessWidget {
  final GoRouter router;
  const ReceiptIQApp({super.key, required this.router});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'ReceiptIQ',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      routerConfig: router,
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(
            padding: mq.padding.copyWith(bottom: mq.viewPadding.bottom),
          ),
          child: child!,
        );
      },
    );
  }
}
