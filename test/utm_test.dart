import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:tactical_car_app/models/geo.dart';
import 'package:tactical_car_app/models/utm.dart';

void main() {
  test('matches the MGRS library digits across Europe', () {
    for (final (lat, lon) in [
      (50.087451, 14.420671), // Praha
      (49.195060, 16.606837), // Brno
      (48.208490, 16.372080), // Wien
      (52.520008, 13.404954), // Berlin
      (-33.8688, 151.2093), // Sydney (south)
    ]) {
      final utm = toUtm(lat, lon);
      final mgrs = formatMgrs(lat, lon).split(' ');
      final easting = int.parse(mgrs[2]);
      final northing = int.parse(mgrs[3]);
      expect(
        (utm.easting % 100000 - easting).abs(),
        lessThan(1.5),
        reason: '$lat,$lon',
      );
      expect(
        (utm.northing % 100000 - northing).abs(),
        lessThan(1.5),
        reason: '$lat,$lon',
      );
      expect(mgrs[0].startsWith('${utm.zone}'), isTrue);
    }
  });

  test('round-trips within millimetres', () {
    for (final (lat, lon) in [
      (50.087451, 14.420671),
      (-12.5, 130.9),
      (64.1, -21.9),
    ]) {
      final back = fromUtm(toUtm(lat, lon));
      expect(distanceKm(LatLng(lat, lon), back) * 1000, lessThan(0.01));
    }
  });

  test('a point can be expressed in a neighbouring zone', () {
    final own = toUtm(50.0, 17.9);
    final forced = toUtm(50.0, 17.9, zone: 34);
    expect(own.zone, 33);
    expect(forced.zone, 34);
    expect(
      distanceKm(fromUtm(forced), const LatLng(50.0, 17.9)) * 1000,
      lessThan(0.01),
    );
  });
}
