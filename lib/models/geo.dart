import 'dart:math' as math;

import 'package:latlong2/latlong.dart';
import 'package:mgrs_dart/mgrs_dart.dart';

const _earthRadiusKm = 6371.0088;

double _degToRad(double degrees) => degrees * math.pi / 180;

/// Great-circle (haversine) distance in kilometres.
double distanceKm(LatLng from, LatLng to) {
  final lat1 = _degToRad(from.latitude);
  final lat2 = _degToRad(to.latitude);
  final deltaLat = _degToRad(to.latitude - from.latitude);
  final deltaLon = _degToRad(to.longitude - from.longitude);
  final a =
      math.sin(deltaLat / 2) * math.sin(deltaLat / 2) +
      math.cos(lat1) *
          math.cos(lat2) *
          math.sin(deltaLon / 2) *
          math.sin(deltaLon / 2);
  return _earthRadiusKm * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

/// Initial true bearing from [from] to [to], 0–360°.
double bearingDeg(LatLng from, LatLng to) {
  final lat1 = _degToRad(from.latitude);
  final lat2 = _degToRad(to.latitude);
  final deltaLon = _degToRad(to.longitude - from.longitude);
  final y = math.sin(deltaLon) * math.cos(lat2);
  final x =
      math.cos(lat1) * math.sin(lat2) -
      math.sin(lat1) * math.cos(lat2) * math.cos(deltaLon);
  return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
}

final _mgrsPattern = RegExp(r'^(\d{1,2}[C-X])([A-Z]{2})(\d{5})(\d{5})$');

/// 1 m MGRS grouped for reading aloud, e.g. `33U VR 58556 48514`.
String formatMgrs(double latitude, double longitude) {
  final raw = Mgrs.forward([longitude, latitude], 5).toUpperCase();
  final match = _mgrsPattern.firstMatch(raw);
  if (match == null) {
    return raw;
  }
  return '${match.group(1)} ${match.group(2)} ${match.group(3)} ${match.group(4)}';
}

/// Parses an MGRS reference (spaces allowed); null when it is not valid.
LatLng? parseMgrs(String value) {
  final compact = value.replaceAll(RegExp(r'\s+'), '').toUpperCase();
  if (compact.isEmpty) {
    return null;
  }
  try {
    final point = Mgrs.toPoint(compact);
    return LatLng(point[1], point[0]);
  } catch (_) {
    return null;
  }
}

/// Point reached from [from] after [distanceM] metres on [bearing] degrees
/// (great-circle, spherical earth).
LatLng destination(LatLng from, double bearing, double distanceM) {
  final angular = distanceM / 1000 / _earthRadiusKm;
  final theta = _degToRad(bearing);
  final lat1 = _degToRad(from.latitude);
  final lon1 = _degToRad(from.longitude);
  final lat2 = math.asin(
    math.sin(lat1) * math.cos(angular) +
        math.cos(lat1) * math.sin(angular) * math.cos(theta),
  );
  final lon2 =
      lon1 +
      math.atan2(
        math.sin(theta) * math.sin(angular) * math.cos(lat1),
        math.cos(angular) - math.sin(lat1) * math.sin(lat2),
      );
  return LatLng(
    lat2 * 180 / math.pi,
    ((lon2 * 180 / math.pi) + 540) % 360 - 180,
  );
}
