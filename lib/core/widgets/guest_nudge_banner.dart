import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A dismissible banner shown to anonymous (guest) users that encourages them
/// to create a free account to keep their receipts permanently.
///
/// Dismissal is per-session only — the banner reappears on the next launch
/// until the user converts to a real account.
class GuestNudgeBanner extends StatefulWidget {
  const GuestNudgeBanner({super.key});

  @override
  State<GuestNudgeBanner> createState() => _GuestNudgeBannerState();
}

class _GuestNudgeBannerState extends State<GuestNudgeBanner> {
  bool _dismissed = false;

  bool get _isAnon {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      return user == null || user.isAnonymous;
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_dismissed || !_isAnon) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF86EFAC), width: 1),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_outlined,
              size: 18, color: Color(0xFF16A34A)),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: const TextStyle(fontSize: 12.5, height: 1.4),
                children: const [
                  TextSpan(
                    text: 'Your receipts are temporary. ',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF15803D)),
                  ),
                  TextSpan(
                    text: 'Create a free account to save them permanently.',
                    style: TextStyle(color: Color(0xFF166534)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => context.push('/auth'),
            child: const Text(
              'Save →',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: Color(0xFF16A34A),
              ),
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: () => setState(() => _dismissed = true),
            child: const Icon(Icons.close,
                size: 16, color: Color(0xFF86EFAC)),
          ),
        ],
      ),
    );
  }
}
