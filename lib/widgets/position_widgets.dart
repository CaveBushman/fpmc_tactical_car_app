import 'package:flutter/material.dart';

import '../models/mesh_node.dart';
import '../services/location_service.dart';
import '../theme.dart';
import 'common_widgets.dart';

/// One-line own-position readout for small screens; tap to expand.
class PositionChip extends StatelessWidget {
  const PositionChip({
    required this.node,
    this.locationState = LocationState.idle,
    super.key,
  });

  final MeshNode node;
  final LocationState locationState;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.76),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: rangerGreen.withValues(alpha: 0.65)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.my_location, size: 14, color: sand),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              node.mgrs,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontFamily: 'monospace',
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 6),
          GpsStatusBadge(state: locationState, compact: true),
          const SizedBox(width: 2),
          Icon(Icons.expand_more, size: 16, color: sand.withValues(alpha: 0.8)),
        ],
      ),
    );
  }
}

class CoordinatePanel extends StatelessWidget {
  const CoordinatePanel({
    required this.node,
    this.locationState = LocationState.idle,
    this.compact = false,
    super.key,
  });

  final MeshNode node;
  final LocationState locationState;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: compact ? 260 : 285,
      padding: EdgeInsets.all(compact ? 10 : 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: rangerGreen.withValues(alpha: 0.65)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'VLASTNÍ POZICE',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: compact ? 10 : 11,
                    color: sand,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              GpsStatusBadge(state: locationState, compact: compact),
            ],
          ),
          SizedBox(height: compact ? 6 : 8),
          MgrsReadout(value: node.mgrs, compact: compact),
          SizedBox(height: compact ? 4 : 6),
          MonoLine(label: 'LAT', value: node.latitude.toStringAsFixed(6)),
          MonoLine(label: 'LON', value: node.longitude.toStringAsFixed(6)),
          if (!compact) MonoLine(label: 'ALT', value: '${node.altitudeM} m'),
        ],
      ),
    );
  }
}

class GpsStatusBadge extends StatelessWidget {
  const GpsStatusBadge({required this.state, this.compact = false, super.key});

  final LocationState state;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final active = state.status == LocationStatus.active;
    final color = active ? blueForce : dangerRed;
    final accuracy = state.lastFix?.accuracyM;
    final label = active && accuracy != null
        ? 'GPS ±${accuracy.round()} m'
        : state.status.shortLabel;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: compact ? 9 : 10,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

extension LocationStatusLabel on LocationStatus {
  String get shortLabel {
    return switch (this) {
      LocationStatus.idle => 'GPS VYP',
      LocationStatus.searching => 'GPS HLEDÁ',
      LocationStatus.active => 'GPS',
      LocationStatus.serviceDisabled => 'GPS VYPNUTO',
      LocationStatus.permissionDenied ||
      LocationStatus.permissionDeniedForever => 'GPS BEZ PRÁV',
      LocationStatus.unavailable => 'GPS N/A',
    };
  }

  String get description {
    return switch (this) {
      LocationStatus.idle => 'neaktivní',
      LocationStatus.searching => 'hledá signál',
      LocationStatus.active => 'aktivní',
      LocationStatus.serviceDisabled => 'polohové služby jsou vypnuté',
      LocationStatus.permissionDenied => 'oprávnění k poloze zamítnuto',
      LocationStatus.permissionDeniedForever =>
        'oprávnění trvale zamítnuto, povol v nastavení',
      LocationStatus.unavailable => 'nedostupné na tomto zařízení',
    };
  }
}

class MgrsReadout extends StatelessWidget {
  const MgrsReadout({required this.value, required this.compact, super.key});

  final String value;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final parts = value
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    final fields = parts.length >= 4
        ? [
            _MgrsField(label: 'ZONE', value: parts[0]),
            _MgrsField(label: 'GRID', value: parts[1]),
            _MgrsField(label: 'EAST', value: parts[2]),
            _MgrsField(label: 'NORTH', value: parts[3]),
          ]
        : [_MgrsField(label: 'MGRS', value: value)];
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 9 : 10,
        vertical: compact ? 7 : 8,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.38),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: tacticalKhaki.withValues(alpha: 0.26)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'MGRS',
            style: TextStyle(
              fontSize: compact ? 10 : 11,
              color: sand,
              fontWeight: FontWeight.w900,
            ),
          ),
          SizedBox(height: compact ? 4 : 5),
          for (final field in fields)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: compact ? 48 : 54,
                    child: Text(
                      field.label,
                      style: TextStyle(
                        fontSize: compact ? 10 : 11,
                        height: 1.1,
                        color: Colors.white.withValues(alpha: 0.58),
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      field.value,
                      maxLines: 1,
                      overflow: TextOverflow.visible,
                      softWrap: false,
                      style: TextStyle(
                        fontSize: compact ? 14 : 15,
                        height: 1.1,
                        color: Colors.white,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _MgrsField {
  const _MgrsField({required this.label, required this.value});

  final String label;
  final String value;
}
