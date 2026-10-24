import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:tactical_car_app/models/geo.dart';
import 'package:tactical_car_app/models/mesh_node.dart';

MeshNode _node(DateTime lastSeenAt, {bool isSelf = false}) => MeshNode(
  nodeNum: 0x1234,
  callSign: 'TEST-1',
  latitude: 50,
  longitude: 14,
  altitudeM: 200,
  batteryPercent: 80,
  lastSeenAt: lastSeenAt,
  isSelf: isSelf,
);

void main() {
  test('link status ages with wall clock', () {
    final now = DateTime.now();
    expect(_node(now).linkStatus, MeshNodeLinkStatus.ok);
    expect(
      _node(now.subtract(const Duration(minutes: 10))).linkStatus,
      MeshNodeLinkStatus.stale,
    );
    expect(
      _node(now.subtract(const Duration(minutes: 20))).linkStatus,
      MeshNodeLinkStatus.lost,
    );
  });

  test('self node is always OK', () {
    final old = DateTime.now().subtract(const Duration(hours: 2));
    expect(_node(old, isSelf: true).linkStatus, MeshNodeLinkStatus.ok);
  });

  test('round-trips lastSeenAt through JSON', () {
    final seen = DateTime.utc(2026, 10, 23, 10, 15);
    final restored = MeshNode.fromJson(_node(seen).toJson());
    expect(restored.lastSeenAt, seen);
  });

  test('legacy snapshot without timestamp restores as LOST', () {
    final json = _node(DateTime.now()).toJson()
      ..remove('lastSeenAt')
      ..['lastSeenMinutes'] = 0;
    expect(MeshNode.fromJson(json).linkStatus, MeshNodeLinkStatus.lost);
  });

  test('team order: self, then by link status, then nearest', () {
    final now = DateTime.now();
    MeshNode at(String callSign, int minutesAgo, double km) => _node(
      now.subtract(Duration(minutes: minutesAgo)),
    ).copyWith(callSign: callSign, distanceKm: km);
    final nodes = [
      at('LOST-NEAR', 30, 0.5),
      at('OK-FAR', 1, 9),
      at('STALE', 10, 1),
      at('OK-NEAR', 2, 2),
      _node(now, isSelf: true).copyWith(callSign: 'ME'),
    ]..sort(MeshNode.teamOrder);
    expect(nodes.map((n) => n.callSign), [
      'ME',
      'OK-NEAR',
      'OK-FAR',
      'STALE',
      'LOST-NEAR',
    ]);
  });

  test('MGRS is derived from coordinates', () {
    final node = _node(
      DateTime.now(),
    ).copyWith(latitude: 50.087451, longitude: 14.420671);
    expect(node.mgrs, '33U VR 58556 48514');
    expect(node.toJson().containsKey('mgrs'), isFalse);
  });

  test('distance and bearing are measured from self and not persisted', () {
    final self = _node(
      DateTime.now(),
      isSelf: true,
    ).copyWith(latitude: 50.087451, longitude: 14.420671);
    final brno = _node(
      DateTime.now(),
    ).copyWith(latitude: 49.195060, longitude: 16.606837);

    final relative = brno.relativeTo(self);

    expect(relative.distanceKm, closeTo(185.3, 1.0));
    expect(relative.bearingDeg, closeTo(122, 2));
    expect(relative.toJson().containsKey('distanceKm'), isFalse);
    expect(MeshNode.fromJson(relative.toJson()).distanceKm, 0);
  });

  test('geo helpers', () {
    const prague = LatLng(50.087451, 14.420671);
    expect(distanceKm(prague, prague), 0);
    expect(
      bearingDeg(prague, const LatLng(51.087451, 14.420671)),
      closeTo(0, 0.01),
    );
    expect(
      bearingDeg(prague, const LatLng(50.087451, 15.420671)),
      closeTo(90, 0.5),
    );
  });

  test('demo nodes carry distances computed from self', () {
    final nodes = MeshNode.demoNodes(DateTime.now());
    final raven2 = nodes.firstWhere((node) => node.callSign == 'RAVEN-2');
    expect(raven2.distanceKm, closeTo(1.2, 0.2));
  });
}
