import 'package:flutter/foundation.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/env.dart';
import '../../data/models/subscription_tier.dart';

/// Wraps OneSignal push notification SDK.
///
/// Supports both anonymous (guest) and registered users.
/// Tags are used for audience segmentation in the OneSignal dashboard
/// and for targeting transactional notifications from Supabase Edge Functions.
class NotificationService {
  NotificationService._();

  // ── Initialise ─────────────────────────────────────────────────────────────

  static Future<void> initialize() async {
    if (!Env.hasOneSignal) return;
    try {
      OneSignal.Debug.setLogLevel(OSLogLevel.none);
      OneSignal.initialize(Env.oneSignalAppId);

      // Request permission on Android 13+; on older Android it is auto-granted.
      await OneSignal.Notifications.requestPermission(true);

      // Handle notification tap → deep link via stored route key.
      OneSignal.Notifications.addClickListener((event) {
        final route = event.notification.additionalData?['route'] as String?;
        if (route != null) {
          _pendingRoute = route;
        }
      });

      // Tag device as guest immediately — overwritten after auth.
      await _setTag('is_guest', 'true');
    } catch (e) {
      debugPrint('[NotificationService] init error: $e');
    }
  }

  // ── Pending deep-link route (consumed by router on next navigation) ─────────

  static String? _pendingRoute;

  /// Consumes and returns a notification deep-link route if one is waiting.
  static String? consumePendingRoute() {
    final r = _pendingRoute;
    _pendingRoute = null;
    return r;
  }

  // ── Permission ─────────────────────────────────────────────────────────────

  static Future<void> requestPermission() async {
    if (!Env.hasOneSignal) return;
    try {
      await OneSignal.Notifications.requestPermission(true);
    } catch (e) {
      debugPrint('[NotificationService] permission error: $e');
    }
  }

  // ── Tagging ────────────────────────────────────────────────────────────────

  /// Called after successful OTP verification (new sign-in or anonymous upgrade).
  /// Associates the device player with the real Supabase user and sets tier/role tags.
  static Future<void> tagUser(User user, SubscriptionTier tier) async {
    if (!Env.hasOneSignal) return;
    try {
      await OneSignal.User.addTagWithKey('user_id', user.id);
      await OneSignal.User.addTagWithKey('is_guest', 'false');
      await OneSignal.User.addTagWithKey('tier', tier.name);        // free/starter/pro
      await OneSignal.User.addTagWithKey('email', user.email ?? '');
      // Set the OneSignal external user ID to match Supabase UUID for REST API targeting.
      await OneSignal.login(user.id);
    } catch (e) {
      debugPrint('[NotificationService] tagUser error: $e');
    }
  }

  /// Refreshes the tier tag after a purchase or cancellation.
  static Future<void> updateTier(SubscriptionTier tier) async {
    if (!Env.hasOneSignal) return;
    try {
      await OneSignal.User.addTagWithKey('tier', tier.name);
    } catch (e) {
      debugPrint('[NotificationService] updateTier error: $e');
    }
  }

  /// Called on sign-out — clears external user ID so future notifications don't
  /// reach the wrong account on a shared device.
  static Future<void> clearUser() async {
    if (!Env.hasOneSignal) return;
    try {
      await OneSignal.logout();
      await OneSignal.User.addTagWithKey('is_guest', 'true');
      await OneSignal.User.removeTag('user_id');
      await OneSignal.User.removeTag('email');
      await OneSignal.User.removeTag('tier');
    } catch (e) {
      debugPrint('[NotificationService] clearUser error: $e');
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  static Future<void> _setTag(String key, String value) async {
    try {
      await OneSignal.User.addTagWithKey(key, value);
    } catch (_) {}
  }
}
