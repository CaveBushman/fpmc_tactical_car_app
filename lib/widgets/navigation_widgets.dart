import 'package:flutter/material.dart';

import '../models/navigation.dart';
import '../theme.dart';

class NavigationTargetStrip extends StatelessWidget {
  const NavigationTargetStrip({
    required this.solutions,
    this.onShareWaypoint,
    this.compact = false,
    super.key,
  });

  final List<TacticalNavSolution> solutions;
  final ValueChanged<TacticalWaypoint>? onShareWaypoint;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final visibleSolutions = solutions.take(compact ? 4 : 5).toList();
    if (compact) {
      return ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: visibleSolutions.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) => SizedBox(
          width: 245,
          child: NavigationTargetCard(
            solution: visibleSolutions[index],
            onShareWaypoint: onShareWaypoint,
            compact: true,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Navigace',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 136,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: visibleSolutions.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) => SizedBox(
              width: 260,
              child: NavigationTargetCard(
                solution: visibleSolutions[index],
                onShareWaypoint: onShareWaypoint,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class NavigationCueBadge extends StatelessWidget {
  const NavigationCueBadge({required this.solution, super.key});

  final TacticalNavSolution solution;

  @override
  Widget build(BuildContext context) {
    final color = solution.priority ? dangerRed : solution.kind.color;
    return Container(
      width: 160,
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.76),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.42)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.near_me_outlined, size: 15, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  solution.label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            'AZ ${solution.bearingDeg.toStringAsFixed(0)}° | ${solution.distanceKm.toStringAsFixed(1)} km',
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class NavigationTargetCard extends StatelessWidget {
  const NavigationTargetCard({
    required this.solution,
    this.onShareWaypoint,
    this.compact = false,
    super.key,
  });

  final TacticalNavSolution solution;
  final ValueChanged<TacticalWaypoint>? onShareWaypoint;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final color = solution.priority ? dangerRed : solution.kind.color;
    final waypoint = solution.waypoint;
    return Card(
      child: Padding(
        padding: EdgeInsets.all(compact ? 9 : 11),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  height: compact ? 30 : 34,
                  width: compact ? 30 : 34,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.13),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: color.withValues(alpha: 0.4)),
                  ),
                  child: Icon(solution.icon, color: color, size: 18),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${solution.label} | ${solution.kind.label}',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: compact ? 12 : 13,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        solution.mgrs,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: sand,
                          fontSize: compact ? 10 : 11,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                if (waypoint != null && onShareWaypoint != null) ...[
                  const SizedBox(width: 6),
                  IconButton.filledTonal(
                    key: ValueKey('share-nav-${waypoint.code}'),
                    tooltip: 'Sdílet ${waypoint.code}',
                    onPressed: () => onShareWaypoint!(waypoint),
                    style: IconButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: rangerGreen.withValues(alpha: 0.68),
                      fixedSize: Size(compact ? 32 : 34, compact ? 32 : 34),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(7),
                      ),
                    ),
                    icon: const Icon(Icons.send, size: 16),
                  ),
                ],
              ],
            ),
            SizedBox(height: compact ? 7 : 9),
            Row(
              children: [
                Expanded(
                  child: _NavMetric(
                    label: 'AZ',
                    value: '${solution.bearingDeg.toStringAsFixed(0)}°',
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _NavMetric(
                    label: 'DIST',
                    value: '${solution.distanceKm.toStringAsFixed(1)} km',
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _NavMetric(label: 'ETA', value: solution.etaLabel),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _NavMetric extends StatelessWidget {
  const _NavMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.54),
              fontSize: 9,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            value,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

class WaypointStrip extends StatelessWidget {
  const WaypointStrip({
    required this.waypoints,
    required this.onShareWaypoint,
    this.compact = false,
    super.key,
  });

  final List<TacticalWaypoint> waypoints;
  final ValueChanged<TacticalWaypoint> onShareWaypoint;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: waypoints.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) => SizedBox(
          width: 235,
          child: WaypointCard(
            waypoint: waypoints[index],
            onShare: () => onShareWaypoint(waypoints[index]),
            compact: true,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Body mise',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        for (final waypoint in waypoints) ...[
          WaypointCard(
            waypoint: waypoint,
            onShare: () => onShareWaypoint(waypoint),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class WaypointCard extends StatelessWidget {
  const WaypointCard({
    required this.waypoint,
    required this.onShare,
    this.compact = false,
    super.key,
  });

  final TacticalWaypoint waypoint;
  final VoidCallback onShare;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final color = waypoint.priority ? dangerRed : sand;
    return Card(
      child: Padding(
        padding: EdgeInsets.all(compact ? 9 : 12),
        child: Row(
          children: [
            Container(
              height: compact ? 34 : 40,
              width: compact ? 34 : 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: color.withValues(alpha: 0.38)),
              ),
              child: Icon(waypoint.icon, color: color, size: compact ? 18 : 21),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${waypoint.code} | ${waypoint.typeLabel}',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: compact ? 12 : 14,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    waypoint.mgrs,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: sand,
                      fontSize: compact ? 11 : 12,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (!compact) ...[
                    const SizedBox(height: 2),
                    Text(
                      waypoint.note,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.66),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            IconButton.filled(
              key: ValueKey('share-waypoint-${waypoint.code}'),
              tooltip: 'Sdílet ${waypoint.code}',
              onPressed: onShare,
              style: IconButton.styleFrom(
                backgroundColor: rangerGreen,
                foregroundColor: Colors.white,
                fixedSize: Size(compact ? 38 : 42, compact ? 38 : 42),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              icon: const Icon(Icons.send, size: 18),
            ),
          ],
        ),
      ),
    );
  }
}
