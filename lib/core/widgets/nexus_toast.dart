import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/nexus_colors.dart';

enum NexusToastType { info, success, warning, error }

/// The overlay entry of the toast currently on screen, so a new toast
/// replaces it instead of stacking.
OverlayEntry? _activeToast;

/// Shows a short-lived notice banner at the TOP of the screen.
///
/// Deliberately an overlay (not a SnackBar): a floating SnackBar sits at the
/// bottom and swallows every tap underneath it, which blocked the undo bar
/// after a successful commit. The banner is also wrapped in [IgnorePointer],
/// so it can never intercept the buttons below it.
void showNexusToast(
  BuildContext context,
  String message, {
  NexusToastType type = NexusToastType.info,
}) {
  final (Color accent, IconData icon) = switch (type) {
    NexusToastType.success => (
        NexusColors.successSoft,
        Icons.check_circle_outline_rounded,
      ),
    NexusToastType.error => (
        NexusColors.roseSoft,
        Icons.error_outline_rounded,
      ),
    NexusToastType.warning => (
        NexusColors.warningSoft,
        Icons.warning_amber_rounded,
      ),
    NexusToastType.info => (
        NexusColors.primarySoft,
        Icons.info_outline_rounded,
      ),
  };

  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;

  _dismissActiveToast();

  final entry = OverlayEntry(
    builder: (_) => _ToastBanner(
      message: message,
      accent: accent,
      icon: icon,
      onExpired: _dismissActiveToast,
    ),
  );
  _activeToast = entry;
  overlay.insert(entry);
}

void _dismissActiveToast() {
  final active = _activeToast;
  _activeToast = null;
  if (active != null && active.mounted) active.remove();
}

/// The visible banner. Its state owns the dismissal timer, so the timer is
/// cancelled when the overlay itself goes away (tests / navigation).
class _ToastBanner extends StatefulWidget {
  final String message;
  final Color accent;
  final IconData icon;
  final VoidCallback onExpired;

  const _ToastBanner({
    required this.message,
    required this.accent,
    required this.icon,
    required this.onExpired,
  });

  @override
  State<_ToastBanner> createState() => _ToastBannerState();
}

class _ToastBannerState extends State<_ToastBanner> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(seconds: 4), widget.onExpired);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.paddingOf(context).top;
    return Positioned(
      top: topPadding + 10,
      left: 16,
      right: 16,
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          decoration: BoxDecoration(
            color: NexusColors.bgSurface.withOpacity(0.97),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: widget.accent.withOpacity(0.4)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.4),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Icon(widget.icon, color: widget.accent, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.message,
                  style: const TextStyle(
                    color: NexusColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
