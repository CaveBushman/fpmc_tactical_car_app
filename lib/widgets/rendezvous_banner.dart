import 'package:flutter/material.dart';

import '../models/navigation.dart';
import '../models/rendezvous.dart';
import '../theme.dart';

/// "SRAZ RV-1 ve 14:30 · za 25 min · cesta 18 min"; red when the trip
/// takes longer than the time left.
class RendezvousBanner extends StatelessWidget {
  const RendezvousBanner({
    required this.meeting,
    required this.isOwn,
    required this.onClose,
    this.solution,
    this.speedKmh = TacticalNavSolution.walkingKmh,
    this.onNavigate,
    super.key,
  });

  final Rendezvous? meeting;

  /// Set by this user: the close button cancels it for everyone.
  final bool isOwn;
  final VoidCallback onClose;
  final TacticalNavSolution? solution;
  final double speedKmh;
  final VoidCallback? onNavigate;

  @override
  Widget build(BuildContext context) {
    final meeting = this.meeting;
    if (meeting == null) {
      return const SizedBox.shrink();
    }
    final left = meeting.at.difference(DateTime.now());
    final solution = this.solution;
    final speed = speedKmh < TacticalNavSolution.walkingKmh
        ? TacticalNavSolution.walkingKmh
        : speedKmh;
    final tripMinutes = solution == null
        ? null
        : (solution.distanceKm / speed * 60).ceil();
    final late = tripMinutes != null && tripMinutes > left.inMinutes;
    final subtitle = [
      if (left.isNegative)
        'před ${-left.inMinutes} min'
      else
        'za ${left.inMinutes} min',
      if (tripMinutes != null)
        late ? 'nestihnete: cesta $tripMinutes min' : 'cesta $tripMinutes min'
      else
        'bod není v mapě',
      'od ${meeting.setBy}',
    ].join(' · ');
    return Container(
      key: const ValueKey('rendezvous-banner'),
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 6),
      padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
      decoration: BoxDecoration(
        color: late ? dangerRed : rangerGreen,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.groups, color: Colors.white, size: 26),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'SRAZ ${meeting.code} ve ${meeting.clock}',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
                Text(
                  subtitle,
                  key: const ValueKey('rendezvous-subtitle'),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ],
            ),
          ),
          if (onNavigate != null && solution != null)
            TextButton(
              onPressed: onNavigate,
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              child: const Text('Navigovat'),
            ),
          IconButton(
            key: const ValueKey('rendezvous-close'),
            tooltip: isOwn ? 'Zrušit sraz' : 'Skrýt',
            onPressed: onClose,
            icon: const Icon(Icons.close, color: Colors.white),
          ),
        ],
      ),
    );
  }
}
