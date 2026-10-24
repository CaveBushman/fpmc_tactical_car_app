import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../models/geo.dart' as geo;
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

/// Details of a point tapped on the map: MGRS, coordinates and the
/// azimuth/distance from the own position.
class PointInfoCard extends StatelessWidget {
  const PointInfoCard({
    required this.point,
    required this.from,
    required this.onClose,
    this.onSave,
    this.onShare,
    this.onNavigate,
    super.key,
  });

  final LatLng point;
  final LatLng from;
  final VoidCallback onClose;
  final VoidCallback? onSave;
  final VoidCallback? onShare;
  final VoidCallback? onNavigate;

  @override
  Widget build(BuildContext context) {
    final km = geo.distanceKm(from, point);
    final azimuth = geo.bearingDeg(from, point);
    return Card(
      key: const ValueKey('point-info'),
      color: Colors.black.withValues(alpha: 0.86),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    geo.formatMgrs(point.latitude, point.longitude),
                    style: const TextStyle(
                      color: Colors.white,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Zavřít',
                  visualDensity: VisualDensity.compact,
                  onPressed: onClose,
                  icon: const Icon(Icons.close, size: 20),
                ),
              ],
            ),
            Text(
              '${point.latitude.toStringAsFixed(6)}, '
              '${point.longitude.toStringAsFixed(6)}',
              style: const TextStyle(color: sand, fontFamily: 'monospace'),
            ),
            Text(
              'AZ ${azimuth.toStringAsFixed(0).padLeft(3, '0')}° · '
              '${km < 1 ? '${(km * 1000).round()} m' : '${km.toStringAsFixed(2)} km'} od tebe',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              children: [
                if (onNavigate != null)
                  TextButton.icon(
                    onPressed: onNavigate,
                    icon: const Icon(Icons.navigation_outlined, size: 18),
                    label: const Text('Navigovat sem'),
                  ),
                if (onSave != null)
                  TextButton.icon(
                    onPressed: onSave,
                    icon: const Icon(Icons.add_location_alt_outlined, size: 18),
                    label: const Text('Uložit bod'),
                  ),
                if (onShare != null)
                  TextButton.icon(
                    onPressed: onShare,
                    icon: const Icon(Icons.send, size: 18),
                    label: const Text('Poslat skupině'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Asks for coordinates (MGRS, short MGRS relative to [near], or decimal
/// degrees) and returns the point; the target is previewed while typing.
class CoordinateEntryDialog extends StatefulWidget {
  const CoordinateEntryDialog({required this.near, super.key});

  final LatLng near;

  @override
  State<CoordinateEntryDialog> createState() => _CoordinateEntryDialogState();
}

class _CoordinateEntryDialogState extends State<CoordinateEntryDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  LatLng? get _parsed =>
      geo.parseCoordinates(_controller.text, near: widget.near);

  void _submit() {
    final point = _parsed;
    if (point != null) {
      Navigator.of(context).pop(point);
    }
  }

  @override
  Widget build(BuildContext context) {
    final point = _parsed;
    final typed = _controller.text.trim().isNotEmpty;
    return AlertDialog(
      // Scrolls when the keyboard leaves little room (phone in landscape).
      scrollable: true,
      backgroundColor: panelGreen,
      title: const Text('Zadat souřadnice'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const ValueKey('coordinate-input'),
            controller: _controller,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            style: const TextStyle(fontFamily: 'monospace'),
            decoration: const InputDecoration(
              hintText: '33U VR 58335 40478',
              helperText:
                  'MGRS, „VR 58335 40478“, „58335 40478“ nebo 50.01, 14.45',
              helperMaxLines: 2,
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 8),
          Text(
            point != null
                ? '${geo.formatMgrs(point.latitude, point.longitude)} · '
                      '${geo.distanceKm(widget.near, point).toStringAsFixed(1)} km '
                      'AZ ${geo.bearingDeg(widget.near, point).round()}°'
                : typed
                ? 'Neplatné souřadnice'
                : ' ',
            key: const ValueKey('coordinate-preview'),
            style: TextStyle(
              color: point != null ? sand : dangerRed,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Zrušit'),
        ),
        FilledButton(
          onPressed: point == null ? null : _submit,
          child: const Text('Ukázat na mapě'),
        ),
      ],
    );
  }
}

/// Readout for the map ruler: last segment (distance + azimuth) and the
/// whole path.
class MeasurePanel extends StatelessWidget {
  const MeasurePanel({
    required this.points,
    required this.onFromSelf,
    required this.onUndo,
    required this.onClose,
    super.key,
  });

  final List<LatLng> points;
  final VoidCallback onFromSelf;
  final VoidCallback onUndo;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    var totalKm = 0.0;
    for (var i = 1; i < points.length; i++) {
      totalKm += geo.distanceKm(points[i - 1], points[i]);
    }
    String distance(double km) =>
        km < 1 ? '${(km * 1000).round()} m' : '${km.toStringAsFixed(2)} km';
    final String headline;
    if (points.isEmpty) {
      headline = 'Klepni na první bod';
    } else if (points.length == 1) {
      headline = 'Klepni na další bod';
    } else {
      final from = points[points.length - 2];
      final to = points.last;
      headline =
          'Úsek ${distance(geo.distanceKm(from, to))} · '
          'AZ ${geo.bearingDeg(from, to).round().toString().padLeft(3, '0')}°';
    }
    return Card(
      key: const ValueKey('measure-panel'),
      color: Colors.black.withValues(alpha: 0.86),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.straighten, color: sand, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    headline,
                    key: const ValueKey('measure-headline'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Ukončit měření',
                  visualDensity: VisualDensity.compact,
                  onPressed: onClose,
                  icon: const Icon(Icons.close, size: 20),
                ),
              ],
            ),
            if (points.length > 2)
              Text(
                'Celkem ${distance(totalKm)} (${points.length - 1} úseků)',
                key: const ValueKey('measure-total'),
                style: const TextStyle(color: sand),
              ),
            Wrap(
              spacing: 8,
              children: [
                if (points.isEmpty)
                  TextButton.icon(
                    onPressed: onFromSelf,
                    icon: const Icon(Icons.my_location, size: 18),
                    label: const Text('Od mé pozice'),
                  ),
                if (points.isNotEmpty)
                  TextButton.icon(
                    onPressed: onUndo,
                    icon: const Icon(Icons.undo, size: 18),
                    label: const Text('Zpět'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
