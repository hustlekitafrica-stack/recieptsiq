import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/router.dart';
import 'core/config/env.dart';
import 'core/services/notification_service.dart';
import 'core/theme/app_theme.dart';
import 'features/onboarding/onboarding_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Catch uncaught Flutter framework errors (prevents silent black screen in release).
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('FlutterError: ${details.exceptionAsString()}');
  };
  // Catch uncaught platform/async errors.
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('PlatformDispatcher error: $error\n$stack');
    return true;
  };
  // Show a visible red error screen instead of black in release mode.
  ErrorWidget.builder = (FlutterErrorDetails details) {
    return Material(
      color: Colors.white,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'App error — please restart.\n\n${details.exception}',
            style: const TextStyle(color: Colors.red, fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  };

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
  // Timeout prevents the app hanging indefinitely if the network is unavailable.
  if (Env.hasSupabase) {
    try {
      await Supabase.initialize(
        url: Env.supabaseUrl,
        publishableKey: Env.supabaseAnonKey,
      ).timeout(const Duration(seconds: 10));
    } catch (_) {
      // Ignore init errors in MVP; local store still works.
    }
  }

  // Initialise push notifications.
  await NotificationService.initialize();

  runZonedGuarded(
    () => runApp(ProviderScope(
      child: ReceiptIQApp(
        router: createAppRouter(onboarded: onboarded),
      ),
    )),
    (error, stack) {
      debugPrint('Zone error: $error\n$stack');
    },
  );
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
