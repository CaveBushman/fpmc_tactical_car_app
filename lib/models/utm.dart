import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

/// UTM position on WGS84 (Krüger series, mm accuracy within a zone).
class UtmCoordinate {
  const UtmCoordinate({
    required this.zone,
    required this.northern,
    required this.easting,
    required this.northing,
  });

  final int zone;
  final bool northern;
  final double easting;
  final double northing;
}

const _a = 6378137.0;
const _f = 1 / 298.257223563;
const _k0 = 0.9996;
final _n = _f / (2 - _f);
final _bigA = _a / (1 + _n) * (1 + _n * _n / 4 + math.pow(_n, 4) / 64);
final _alpha = [
  _n / 2 - 2 * _n * _n / 3 + 5 * math.pow(_n, 3) / 16,
  13 * _n * _n / 48 - 3 * math.pow(_n, 3) / 5,
  61 * math.pow(_n, 3) / 240,
];
final _beta = [
  _n / 2 - 2 * _n * _n / 3 + 37 * math.pow(_n, 3) / 96,
  _n * _n / 48 + math.pow(_n, 3) / 15,
  17 * math.pow(_n, 3) / 480,
];
final _delta = [
  2 * _n - 2 * _n * _n / 3 - 2 * math.pow(_n, 3),
  7 * _n * _n / 3 - 8 * math.pow(_n, 3) / 5,
  56 * math.pow(_n, 3) / 15,
];

/// Standard UTM zone of a point (without the Norway/Svalbard exceptions,
/// which do not matter for grid drawing at the zone's own meridian).
int utmZone(double longitude) =>
    ((longitude + 180) / 6).floor().clamp(0, 59) + 1;

double _centralMeridian(int zone) => (zone - 1) * 6 - 180 + 3;

double _rad(double degrees) => degrees * math.pi / 180;
double _deg(double radians) => radians * 180 / math.pi;
double _atanh(double x) => 0.5 * math.log((1 + x) / (1 - x));
double _sinh(double x) => (math.exp(x) - math.exp(-x)) / 2;
double _cosh(double x) => (math.exp(x) + math.exp(-x)) / 2;

/// Lat/lon → UTM, optionally forced into [zone] (to draw one zone's grid
/// across a view that straddles a zone boundary).
UtmCoordinate toUtm(double latitude, double longitude, {int? zone}) {
  final z = zone ?? utmZone(longitude);
  final phi = _rad(latitude);
  final lambda = _rad(longitude - _centralMeridian(z));
  final e = math.sqrt(_f * (2 - _f));
  final t = _sinh(_atanh(math.sin(phi)) - e * _atanh(e * math.sin(phi)));
  final xiPrime = math.atan2(t, math.cos(lambda));
  final etaPrime = _atanh(math.sin(lambda) / math.sqrt(1 + t * t));
  var xi = xiPrime;
  var eta = etaPrime;
  for (var j = 1; j <= 3; j++) {
    xi += _alpha[j - 1] * math.sin(2 * j * xiPrime) * _cosh(2 * j * etaPrime);
    eta += _alpha[j - 1] * math.cos(2 * j * xiPrime) * _sinh(2 * j * etaPrime);
  }
  final northern = latitude >= 0;
  return UtmCoordinate(
    zone: z,
    northern: northern,
    easting: 500000 + _k0 * _bigA * eta,
    northing: (northern ? 0 : 10000000) + _k0 * _bigA * xi,
  );
}

/// UTM → lat/lon.
LatLng fromUtm(UtmCoordinate utm) {
  final xi = (utm.northing - (utm.northern ? 0 : 10000000)) / (_k0 * _bigA);
  final eta = (utm.easting - 500000) / (_k0 * _bigA);
  var xiPrime = xi;
  var etaPrime = eta;
  for (var j = 1; j <= 3; j++) {
    xiPrime -= _beta[j - 1] * math.sin(2 * j * xi) * _cosh(2 * j * eta);
    etaPrime -= _beta[j - 1] * math.cos(2 * j * xi) * _sinh(2 * j * eta);
  }
  final chi = math.asin(math.sin(xiPrime) / _cosh(etaPrime));
  var phi = chi;
  for (var j = 1; j <= 3; j++) {
    phi += _delta[j - 1] * math.sin(2 * j * chi);
  }
  final lambda = math.atan2(_sinh(etaPrime), math.cos(xiPrime));
  return LatLng(_deg(phi), _centralMeridian(utm.zone) + _deg(lambda));
}
