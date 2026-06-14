import 'dart:io';

import 'package:flutter/material.dart';

enum PaymentMethodType { playStore, mpesa, pesapal }

class PaymentMethod {
  final PaymentMethodType type;
  final String name;
  final String subtitle;
  final IconData icon;
  final Color color;
  const PaymentMethod({
    required this.type,
    required this.name,
    required this.subtitle,
    required this.icon,
    required this.color,
  });
}

/// Decides which payment methods to show and in which order based on the
/// device locale / region.
class PaymentRoutingService {
  PaymentRoutingService._();

  static const _playStore = PaymentMethod(
    type: PaymentMethodType.playStore,
    name: 'Google Play',
    subtitle: 'Cards & carrier billing via Google Play',
    icon: Icons.play_circle_fill_outlined,
    color: Color(0xFF34A853),
  );

  static const _mpesa = PaymentMethod(
    type: PaymentMethodType.mpesa,
    name: 'M-Pesa',
    subtitle: 'Pay via Safaricom M-Pesa STK Push (Kenya)',
    icon: Icons.phone_android_outlined,
    color: Color(0xFF4CAF50),
  );

  static const _pesapal = PaymentMethod(
    type: PaymentMethodType.pesapal,
    name: 'Pesapal',
    subtitle: 'M-Pesa, Airtel, cards via Pesapal (Kenya/EA)',
    icon: Icons.payment_outlined,
    color: Color(0xFF1565C0),
  );

  /// Returns payment methods ordered by relevance for the current device locale.
  static List<PaymentMethod> methodsForCurrentLocale() {
    final countryCode = _detectCountry();
    switch (countryCode) {
      case 'KE':
        return [_mpesa, _pesapal, _playStore];
      case 'TZ':
      case 'UG':
      case 'RW':
      case 'ET':
      case 'ZM':
        return [_pesapal, _playStore];
      case 'NG':
      case 'GH':
      case 'CI':
      case 'SN':
      case 'CM':
      case 'ZA':
      case 'MZ':
        return [_playStore];
      default:
        return [_playStore];
    }
  }

  static String? _detectCountry() {
    try {
      final locales = Platform.localeName;
      final parts = locales.split('_');
      if (parts.length >= 2) return parts.last.toUpperCase();
    } catch (_) {}
    return null;
  }
}
