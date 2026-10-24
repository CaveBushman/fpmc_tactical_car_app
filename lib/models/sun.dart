import 'dart:math' as math;

/// Sun altitude of the end of civil twilight: below it, it is dark enough
/// to need night vision.
const civilTwilightDeg = -6.0;

/// Sun altitude above the horizon in degrees at [at] (any time zone) for
/// the given position. NOAA's simplified solar position, accurate to a
/// fraction of a degree, which is plenty for switching a display mode.
double sunAltitudeDeg(DateTime at, double latitude, double longitude) {
  final utc = at.toUtc();
  // Days since J2000.0 (2000-01-01 12:00 UTC).
  final days =
      utc.difference(DateTime.utc(2000, 1, 1, 12)).inMilliseconds /
      Duration.millisecondsPerDay;
  final meanLongitude = _norm(280.460 + 0.9856474 * days);
  final meanAnomaly = _rad(_norm(357.528 + 0.9856003 * days));
  final eclipticLongitude = _rad(
    meanLongitude +
        1.915 * math.sin(meanAnomaly) +
        0.020 * math.sin(2 * meanAnomaly),
  );
  final obliquity = _rad(23.439 - 0.0000004 * days);
  final declination = math.asin(
    math.sin(obliquity) * math.sin(eclipticLongitude),
  );
  final rightAscension = math.atan2(
    math.cos(obliquity) * math.sin(eclipticLongitude),
    math.cos(eclipticLongitude),
  );
  // Greenwich mean sidereal time in degrees, then the local hour angle.
  final gmst = _norm(280.46061837 + 360.98564736629 * days);
  final hourAngle = _rad(gmst + longitude) - rightAscension;
  final lat = _rad(latitude);
  final altitude = math.asin(
    math.sin(lat) * math.sin(declination) +
        math.cos(lat) * math.cos(declination) * math.cos(hourAngle),
  );
  return altitude * 180 / math.pi;
}

/// True between the end of civil dusk and the start of civil dawn.
bool isDark(DateTime at, double latitude, double longitude) =>
    sunAltitudeDeg(at, latitude, longitude) < civilTwilightDeg;

double _rad(double degrees) => degrees * math.pi / 180;
double _norm(double degrees) => degrees % 360;
