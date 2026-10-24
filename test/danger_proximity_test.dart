import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:tactical_car_app/controllers/danger_proximity.dart';
import 'package:tactical_car_app/models/geo.dart' as geo;
import 'package:tactical_car_app/models/navigation.dart';

const _point = LatLng(50.0, 14.0);

TacticalWaypoint _waypoint(
  String code, {
  TacticalWaypointType type = TacticalWaypointType.danger,
}) => TacticalWaypoint(
  code: code,
  type: type,
  latitude: _point.latitude,
  longitude: _point.longitude,
  note: 'mina',
);

/// Position [metres] due south of the point.
LatLng _south(double metres) => geo.destination(_point, 180, metres);

void main() {
  test('alerts once on entry and clears only beyond the outer radius', () {
    final proximity = DangerProximity();
    final points = [_waypoint('DNG-1')];

    expect(proximity.update(_south(500), points), isEmpty);
    expect(proximity.warnings, isEmpty);

    final entered = proximity.update(_south(250), points);
    expect(entered.single.waypoint.code, 'DNG-1');
    expect(entered.single.distanceM, closeTo(250, 2));
    expect(entered.single.bearingDeg, closeTo(0, 1)); // point is north

    // Jitter between 300 and 450 m keeps the warning without a new alert.
    expect(proximity.update(_south(400), points), isEmpty);
    expect(proximity.warnings, hasLength(1));

    expect(proximity.update(_south(460), points), isEmpty);
    expect(proximity.warnings, isEmpty);

    expect(proximity.update(_south(200), points), hasLength(1));
  });

  test('dismiss hides the warning until the next approach', () {
    final proximity = DangerProximity();
    final points = [_waypoint('DNG-1')];
    proximity.update(_south(100), points);
    proximity.dismiss('DNG-1');
    expect(proximity.warnings, isEmpty);

    proximity.update(_south(50), points);
    expect(proximity.warnings, isEmpty);

    proximity.update(_south(600), points);
    proximity.update(_south(100), points);
    expect(proximity.warnings, hasLength(1));
  });

  test('ignores other point types and SOS points', () {
    final proximity = DangerProximity();
    final entered = proximity.update(_south(10), [
      _waypoint('RV-1', type: TacticalWaypointType.rally),
      _waypoint('SOS-ALFA'),
    ]);
    expect(entered, isEmpty);
  });
}
