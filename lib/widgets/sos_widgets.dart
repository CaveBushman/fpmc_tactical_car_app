import 'package:flutter/material.dart';

import '../controllers/danger_proximity.dart';
import '../models/sos.dart';
import '../theme.dart';

/// Asks before starting a distress call (it repeats until cancelled).
Future<bool> confirmSosStart(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: panelGreen,
      icon: const Icon(Icons.sos, color: dangerRed, size: 40),
      title: const Text('Spustit SOS?'),
      content: const Text(
        'Výzva s tvou polohou se pošle celé skupině a bude se opakovat '
        'každou minutu, dokud ji nezrušíš.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Zpět'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: FilledButton.styleFrom(backgroundColor: dangerRed),
          child: const Text('SPUSTIT SOS'),
        ),
      ],
    ),
  );
  return confirmed == true;
}

/// Red banners: our own active call and teammates' calls.
class SosBanners extends StatelessWidget {
  const SosBanners({
    required this.ownActive,
    required this.alerts,
    required this.onCancelOwn,
    required this.onAcknowledge,
    super.key,
  });

  final bool ownActive;
  final List<SosAlert> alerts;
  final VoidCallback onCancelOwn;
  final ValueChanged<SosAlert> onAcknowledge;

  @override
  Widget build(BuildContext context) {
    if (!ownActive && alerts.isEmpty) {
      return const SizedBox.shrink();
    }
    final now = DateTime.now();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (ownActive)
          _Banner(
            key: const ValueKey('sos-own'),
            icon: Icons.sos,
            title: 'SOS AKTIVNÍ',
            subtitle: 'Výzva s polohou se opakuje každou minutu',
            actionLabel: 'Zrušit',
            onAction: onCancelOwn,
          ),
        for (final alert in alerts)
          _Banner(
            key: ValueKey('sos-alert-${alert.callSign}'),
            icon: Icons.warning_amber,
            title: 'SOS: ${alert.callSign}',
            subtitle: [
              if (alert.mgrs != null) alert.mgrs!,
              'před ${now.difference(alert.lastAt).inMinutes} min',
            ].join(' · '),
            actionLabel: 'Beru',
            onAction: () => onAcknowledge(alert),
          ),
      ],
    );
  }
}

/// One red bar per DANGER point we are close to, with "Beru" to hide it.
class DangerBanners extends StatelessWidget {
  const DangerBanners({
    required this.warnings,
    required this.onDismiss,
    super.key,
  });

  final List<DangerWarning> warnings;
  final ValueChanged<DangerWarning> onDismiss;

  @override
  Widget build(BuildContext context) {
    if (warnings.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final warning in warnings)
          _Banner(
            key: ValueKey('danger-${warning.waypoint.code}'),
            icon: Icons.dangerous,
            title: 'NEBEZPEČÍ ${warning.waypoint.code}',
            subtitle: [
              '${warning.distanceM.round()} m',
              'AZ ${warning.bearingDeg.round()}°',
              if (warning.waypoint.note.isNotEmpty) warning.waypoint.note,
            ].join(' · '),
            actionLabel: 'Beru',
            onAction: () => onDismiss(warning),
          ),
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onAction,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 6),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: dangerRed,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 28),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
                Text(
                  subtitle,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ],
            ),
          ),
          FilledButton(
            onPressed: onAction,
            style: FilledButton.styleFrom(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
            ),
            child: Text(actionLabel),
          ),
        ],
      ),
    );
  }
}

/// Button that fires only after being held for [holdFor], with a filling
/// progress bar, so a destructive action cannot happen by a stray tap.
class HoldToConfirmButton extends StatefulWidget {
  const HoldToConfirmButton({
    required this.label,
    required this.onConfirmed,
    this.holdFor = const Duration(seconds: 3),
    super.key,
  });

  final String label;
  final VoidCallback onConfirmed;
  final Duration holdFor;

  @override
  State<HoldToConfirmButton> createState() => _HoldToConfirmButtonState();
}

class _HoldToConfirmButtonState extends State<HoldToConfirmButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _progress =
      AnimationController(vsync: this, duration: widget.holdFor)
        ..addStatusListener((status) {
          if (status == AnimationStatus.completed) {
            widget.onConfirmed();
          }
        });

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _progress.forward(from: 0),
      onPointerUp: (_) {
        if (!_progress.isCompleted) {
          _progress.reverse();
        }
      },
      onPointerCancel: (_) => _progress.reverse(),
      child: AnimatedBuilder(
        animation: _progress,
        builder: (context, _) => Stack(
          alignment: Alignment.center,
          children: [
            Container(
              height: 56,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: dangerRed, width: 2),
              ),
            ),
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: _progress.value,
                  child: const ColoredBox(color: dangerRed),
                ),
              ),
            ),
            Text(
              widget.label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
