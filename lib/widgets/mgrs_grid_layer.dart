import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/utm.dart';
import '../theme.dart';

/// Grid line spacing in metres for a zoom level; null = no grid.
int? mgrsGridSpacing(double zoom) {
  if (zoom >= 12.5) return 1000;
  if (zoom >= 9.5) return 10000;
  if (zoom >= 6.5) return 100000;
  return null;
}

/// MGRS/UTM grid lines of the visible area, labelled with the principal
/// digits used in MGRS references (e.g. "58" for easting 358 000 on a 1 km
/// grid). Drawn in the UTM zone of the map centre.
class MgrsGridLayer extends StatelessWidget {
  const MgrsGridLayer({super.key});

  static const _maxLines = 60;

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    var spacing = mgrsGridSpacing(camera.zoom);
    if (spacing == null) {
      return const SizedBox.shrink();
    }
    final bounds = camera.visibleBounds;
    final center = camera.center;
    final zone = utmZone(center.longitude);
    final northern = center.latitude >= 0;

    // Extent of the view in the centre zone (corners and edge midpoints).
    final samples = [
      for (final lat in [bounds.south, center.latitude, bounds.north])
        for (final lon in [bounds.west, center.longitude, bounds.east])
          toUtm(lat, lon, zone: zone),
    ];
    final eMin = samples.map((u) => u.easting).reduce((a, b) => a < b ? a : b);
    final eMax = samples.map((u) => u.easting).reduce((a, b) => a > b ? a : b);
    final nMin = samples.map((u) => u.northing).reduce((a, b) => a < b ? a : b);
    final nMax = samples.map((u) => u.northing).reduce((a, b) => a > b ? a : b);
    while ((eMax - eMin) / spacing! > _maxLines ||
        (nMax - nMin) / spacing > _maxLines) {
      spacing *= 10;
    }

    LatLng at(double easting, double northing) => fromUtm(
      UtmCoordinate(
        zone: zone,
        northern: northern,
        easting: easting,
        northing: northing,
      ),
    );

    final eastings = [
      for (var e = (eMin / spacing).ceil() * spacing; e <= eMax; e += spacing)
        e,
    ];
    final northings = [
      for (var n = (nMin / spacing).ceil() * spacing; n <= nMax; n += spacing)
        n,
    ];

    Polyline line(List<LatLng> points, int value) {
      final major = value % (spacing! * 10) == 0;
      return Polyline(
        points: points,
        strokeWidth: major ? 1.6 : 0.8,
        color: sand.withValues(alpha: major ? 0.55 : 0.32),
      );
    }

    const steps = 8;
    final polylines = [
      for (final e in eastings)
        line([
          for (var i = 0; i <= steps; i++)
            at(e.toDouble(), nMin + (nMax - nMin) * i / steps),
        ], e),
      for (final n in northings)
        line([
          for (var i = 0; i <= steps; i++)
            at(eMin + (eMax - eMin) * i / steps, n.toDouble()),
        ], n),
    ];

    final labelEdgeN = nMin + (nMax - nMin) * 0.04;
    final labelEdgeE = eMin + (eMax - eMin) * 0.04;
    final markers = spacing >= 100000
        ? const <Marker>[]
        : [
            for (final e in eastings)
              Marker(
                point: at(e.toDouble(), labelEdgeN),
                width: 30,
                height: 16,
                child: _GridLabel(gridLabel(e, spacing)),
              ),
            for (final n in northings)
              Marker(
                point: at(labelEdgeE, n.toDouble()),
                width: 30,
                height: 16,
                child: _GridLabel(gridLabel(n, spacing)),
              ),
          ];

    return IgnorePointer(
      child: Stack(
        children: [
          PolylineLayer(polylines: polylines),
          MarkerLayer(markers: markers),
        ],
      ),
    );
  }
}

/// Principal digits of a grid line inside its 100 km square: "58" for
/// 358 000 m on a 1 km grid, "5" for 350 000 m on a 10 km grid.
String gridLabel(int metres, int spacing) {
  final within = metres % 100000;
  return spacing >= 10000
      ? '${within ~/ 10000}'
      : (within ~/ 1000).toString().padLeft(2, '0');
}

class _GridLabel extends StatelessWidget {
  const _GridLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        color: Colors.black.withValues(alpha: 0.6),
        child: Text(
          text,
          style: const TextStyle(
            color: sand,
            fontSize: 10,
            fontWeight: FontWeight.w800,
            fontFamily: 'monospace',
          ),
        ),
      ),
    );
  }
}
