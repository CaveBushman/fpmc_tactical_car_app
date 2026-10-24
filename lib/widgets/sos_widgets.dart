import 'package:flutter/material.dart';

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
