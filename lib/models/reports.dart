import 'package:latlong2/latlong.dart';

import 'geo.dart';

/// A CONTACT report as sent by the Messages screen:
/// `CONTACT | MGRS <observer> | DIR <deg> | DIST <m> m | TYPE … | SIZE … | note`.
class ContactReport {
  const ContactReport({
    required this.observer,
    required this.bearingDeg,
    required this.distanceM,
    required this.contactType,
    required this.size,
    required this.note,
  });

  final LatLng observer;
  final double bearingDeg;
  final double distanceM;
  final String contactType;
  final String size;
  final String note;

  /// Estimated contact position from observer, bearing and distance.
  LatLng get position => destination(observer, bearingDeg, distanceM);

  static ContactReport? parse(String text) {
    final parts = text.split('|').map((part) => part.trim()).toList();
    if (parts.isEmpty || parts.first != 'CONTACT') {
      return null;
    }
    String? field(String key) {
      for (final part in parts) {
        if (part.startsWith('$key ')) {
          return part.substring(key.length + 1).trim();
        }
      }
      return null;
    }

    final observer = parseMgrs(field('MGRS') ?? '');
    final bearing = double.tryParse(field('DIR') ?? '');
    final distance = double.tryParse(
      (field('DIST') ?? '').replaceAll(RegExp(r'\s*m$'), ''),
    );
    // Free-text directions ("SV") or ranges cannot be plotted.
    if (observer == null ||
        bearing == null ||
        distance == null ||
        bearing < 0 ||
        bearing > 360 ||
        distance <= 0 ||
        distance > 20000) {
      return null;
    }
    final known = {'CONTACT', 'MGRS', 'DIR', 'DIST', 'TYPE', 'SIZE'};
    final note = parts
        .skip(1)
        .where((part) => !known.any((key) => part.startsWith('$key ')))
        .join(' | ');
    return ContactReport(
      observer: observer,
      bearingDeg: bearing,
      distanceM: distance,
      contactType: field('TYPE') ?? 'NEZNÁMÝ',
      size: field('SIZE') ?? '?',
      note: note,
    );
  }
}
