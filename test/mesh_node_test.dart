import 'package:flutter_test/flutter_test.dart';
import 'package:tactical_car_app/main.dart';

MeshNode _node(DateTime lastSeenAt, {bool isSelf = false}) => MeshNode(
  nodeNum: 0x1234,
  callSign: 'TEST-1',
  latitude: 50,
  longitude: 14,
  altitudeM: 200,
  mgrs: '33U VR 00000 00000',
  batteryPercent: 80,
  lastSeenAt: lastSeenAt,
  distanceKm: 0,
  bearingDeg: 0,
  mapOffset: Offset.zero,
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
}
