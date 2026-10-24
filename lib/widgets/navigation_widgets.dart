import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../models/geo.dart';
import '../models/navigation.dart';
import '../theme.dart';

class NavigationTargetStrip extends StatelessWidget {
  const NavigationTargetStrip({
    required this.solutions,
    this.onShareWaypoint,
    this.onNavigate,
    this.compact = false,
    super.key,
  });

  final List<TacticalNavSolution> solutions;
  final ValueChanged<TacticalWaypoint>? onShareWaypoint;
  final ValueChanged<NavTarget>? onNavigate;
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
            onNavigate: onNavigate,
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
                onNavigate: onNavigate,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class NavigationCueBadge extends StatelessWidget {
  const NavigationCueBadge({required this.solution, this.onClear, super.key});

  final TacticalNavSolution solution;

  /// Set when [solution] is the chosen target: shows a close button.
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final chosen = onClear != null;
    final color = solution.priority ? dangerRed : solution.kind.color;
    final badge = Container(
      width: chosen ? null : 160,
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
              Icon(
                chosen ? Icons.navigation : Icons.near_me_outlined,
                size: 15,
                color: color,
              ),
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
            'AZ ${solution.bearingDeg.toStringAsFixed(0)}° | ${formatDistance(solution.distanceKm)}',
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
    if (!chosen) {
      return badge;
    }
    return Row(
      children: [
        Expanded(child: badge),
        IconButton(
          key: const ValueKey('clear-nav-target'),
          tooltip: 'Ukončit navigaci',
          onPressed: onClear,
          icon: const Icon(Icons.close),
        ),
      ],
    );
  }
}

/// Metres below 1 km, otherwise kilometres with one decimal.
String formatDistance(double km) =>
    km < 1 ? '${(km * 1000).round()} m' : '${km.toStringAsFixed(1)} km';

class NavigationTargetCard extends StatelessWidget {
  const NavigationTargetCard({
    required this.solution,
    this.onShareWaypoint,
    this.onNavigate,
    this.compact = false,
    super.key,
  });

  final TacticalNavSolution solution;
  final ValueChanged<TacticalWaypoint>? onShareWaypoint;
  final ValueChanged<NavTarget>? onNavigate;
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
                if (onNavigate != null) ...[
                  const SizedBox(width: 6),
                  IconButton.filledTonal(
                    key: ValueKey('navigate-${solution.label}'),
                    tooltip: 'Navigovat k ${solution.label}',
                    onPressed: () => onNavigate!(solution.target),
                    style: IconButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: rangerGreen.withValues(alpha: 0.68),
                      fixedSize: Size(compact ? 32 : 34, compact ? 32 : 34),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(7),
                      ),
                    ),
                    icon: const Icon(Icons.navigation_outlined, size: 16),
                  ),
                ],
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
    this.onDeleteWaypoint,
    this.onEditWaypoint,
    this.compact = false,
    super.key,
  });

  final List<TacticalWaypoint> waypoints;
  final ValueChanged<TacticalWaypoint> onShareWaypoint;
  final ValueChanged<TacticalWaypoint>? onDeleteWaypoint;
  final ValueChanged<TacticalWaypoint>? onEditWaypoint;
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
        Text(
          'Nový bod: dlouhý stisk na mapě',
          style: TextStyle(
            fontSize: 12,
            color: Colors.white.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(height: 8),
        for (final waypoint in waypoints) ...[
          WaypointCard(
            waypoint: waypoint,
            onShare: () => onShareWaypoint(waypoint),
            onDelete: onDeleteWaypoint == null
                ? null
                : () => onDeleteWaypoint!(waypoint),
            onEdit: onEditWaypoint == null
                ? null
                : () => onEditWaypoint!(waypoint),
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
    this.onDelete,
    this.onEdit,
    this.compact = false,
    super.key,
  });

  final TacticalWaypoint waypoint;
  final VoidCallback onShare;
  final VoidCallback? onDelete;
  final VoidCallback? onEdit;
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
                      waypoint.sharedBy == null
                          ? waypoint.note
                          : '${waypoint.note} (od ${waypoint.sharedBy})'.trim(),
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
            if (onEdit != null)
              IconButton(
                key: ValueKey('edit-waypoint-${waypoint.code}'),
                tooltip: 'Upravit ${waypoint.code}',
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, size: 20),
                color: Colors.white.withValues(alpha: 0.7),
              ),
            if (onDelete != null)
              IconButton(
                key: ValueKey('delete-waypoint-${waypoint.code}'),
                tooltip: 'Smazat ${waypoint.code}',
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline, size: 20),
                color: Colors.white.withValues(alpha: 0.7),
              ),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet for a new waypoint at [position], or for changing type
/// and note of [editing].
class WaypointEditorSheet extends StatefulWidget {
  const WaypointEditorSheet({required this.position, this.editing, super.key});

  final LatLng position;
  final TacticalWaypoint? editing;

  @override
  State<WaypointEditorSheet> createState() => _WaypointEditorSheetState();
}

class _WaypointEditorSheetState extends State<WaypointEditorSheet> {
  late final TextEditingController _codeController = TextEditingController(
    text: widget.editing?.code,
  );
  late final TextEditingController _noteController = TextEditingController(
    text: widget.editing?.note,
  );
  late TacticalWaypointType _type =
      widget.editing?.type ?? TacticalWaypointType.rally;
  bool _share = true;

  @override
  void dispose() {
    _codeController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final position = widget.position;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        14,
        16,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.editing == null
                  ? 'Nový bod'
                  : 'Upravit ${widget.editing!.code}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            Text(
              formatMgrs(position.latitude, position.longitude),
              style: const TextStyle(
                color: sand,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final type in TacticalWaypointType.values)
                  ChoiceChip(
                    label: Text(type.label),
                    selected: _type == type,
                    onSelected: (_) => setState(() => _type = type),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _codeController,
              // The code identifies the point on teammates' maps.
              enabled: widget.editing == null,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: 'Kód',
                hintText: '${_type.label}-1 (automaticky)',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _noteController,
              decoration: const InputDecoration(
                labelText: 'Poznámka',
                border: OutlineInputBorder(),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _share,
              onChanged: (value) => setState(() => _share = value),
              title: Text(
                widget.editing == null
                    ? 'Hned sdílet do skupiny'
                    : 'Poslat změnu skupině',
              ),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(
                WaypointDraft(
                  type: _type,
                  latitude: position.latitude,
                  longitude: position.longitude,
                  code: _codeController.text,
                  note: _noteController.text,
                  share: _share,
                  editing: widget.editing,
                ),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: rangerGreen,
                minimumSize: const Size.fromHeight(48),
              ),
              icon: const Icon(Icons.add_location_alt_outlined),
              label: Text(
                widget.editing == null ? 'Uložit bod' : 'Uložit změny',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
