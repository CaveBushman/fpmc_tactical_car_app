import 'dart:math' as math;

import 'package:latlong2/latlong.dart';
import 'package:mgrs_dart/mgrs_dart.dart';

import 'utm.dart';

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
  final match = RegExp(r'^(\d{1,2})[C-X][A-Z]{2}(\d*)$').firstMatch(compact);
  final digits = match?.group(2) ?? '';
  if (match == null || digits.length.isOdd || digits.length > 10) {
    return null;
  }
  try {
    final corner = Mgrs.toPoint(compact);
    // MGRS names a square; take its centre so formatting the result gives
    // back the same digits instead of the south-west corner minus 1 m.
    final half = math.pow(10, 5 - digits.length ~/ 2) / 2;
    final zone = int.parse(match.group(1)!);
    final utm = toUtm(corner[1], corner[0], zone: zone);
    return fromUtm(
      UtmCoordinate(
        zone: zone,
        northern: utm.northern,
        easting: utm.easting + half,
        northing: utm.northing + half,
      ),
    );
  } catch (_) {
    return null;
  }
}

/// Coordinates typed by hand: full MGRS ("33U VR 58335 40478"), MGRS
/// without the zone ("VR 58335 40478") or without zone and square
/// ("58335 40478") taken from [near], or decimal degrees
/// ("50.0123, 14.4567"). Null when it cannot be read.
LatLng? parseCoordinates(String input, {LatLng? near}) {
  final text = input.trim().toUpperCase();
  if (text.isEmpty) {
    return null;
  }
  final decimal = RegExp(
    r'^(-?\d{1,2}(?:[.,]\d+)?)\s*[,;\s]\s*(-?\d{1,3}(?:[.,]\d+)?)$',
  ).firstMatch(text);
  if (decimal != null && (text.contains('.') || text.contains(';'))) {
    final lat = double.tryParse(decimal.group(1)!.replaceAll(',', '.'));
    final lon = double.tryParse(decimal.group(2)!.replaceAll(',', '.'));
    if (lat != null && lon != null && lat.abs() <= 90 && lon.abs() <= 180) {
      return LatLng(lat, lon);
    }
  }
  final parts = text.split(RegExp(r'\s+'));
  final digits = RegExp(r'^\d+$');
  // Easting and northing typed apart must have the same precision.
  if (parts.length >= 2 &&
      digits.hasMatch(parts[parts.length - 1]) &&
      digits.hasMatch(parts[parts.length - 2]) &&
      parts[parts.length - 1].length != parts[parts.length - 2].length) {
    return null;
  }
  final full = parseMgrs(text);
  if (full != null) {
    return full;
  }
  if (near == null) {
    return null;
  }
  // Prefix what is missing from our own MGRS reference.
  final own = formatMgrs(near.latitude, near.longitude).split(' ');
  if (parts.length == 3 &&
      RegExp(r'^[A-Z]{2}$').hasMatch(parts[0]) &&
      digits.hasMatch(parts[1]) &&
      digits.hasMatch(parts[2])) {
    return parseMgrs('${own[0]} $text');
  }
  if (parts.length == 2 && parts.every(digits.hasMatch)) {
    return parseMgrs('${own[0]} ${own[1]} $text');
  }
  return null;
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
