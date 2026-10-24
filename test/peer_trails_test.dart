import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:tactical_car_app/controllers/peer_trails.dart';
import 'package:tactical_car_app/models/mesh_node.dart';

MeshNode _node(int num, double lat, DateTime seen, {bool self = false}) =>
    MeshNode(
      nodeNum: num,
      callSign: 'N$num',
      latitude: lat,
      longitude: 14.0,
      altitudeM: 0,
      lastSeenAt: seen,
      isSelf: self,
    );

void main() {
  final t0 = DateTime(2026, 10, 24, 12);
  DateTime at(int minutes) => t0.add(Duration(minutes: minutes));

  test('records movement of peers only, after 10 m', () {
    final trails = PeerTrails();
    trails.update([
      _node(1, 50.0, at(0), self: true),
      _node(2, 50.0, at(0)),
    ], now: at(0));
    expect(trails.trails, isEmpty); // one point is not a line

    trails.update([_node(2, 50.00005, at(1))], now: at(1)); // ~5 m
    expect(trails.trails, isEmpty);

    trails.update([_node(2, 50.001, at(2))], now: at(2)); // ~110 m
    trails.update([_node(2, 50.002, at(3))], now: at(3));
    expect(trails.trails.keys, [2]);
    expect(trails.trails[2], const [
      LatLng(50.0, 14.0),
      LatLng(50.001, 14.0),
      LatLng(50.002, 14.0),
    ]);
  });

  test('ignores repeated old fixes and keeps only the last 30 minutes', () {
    final trails = PeerTrails();
    trails.update([_node(2, 50.0, at(0))], now: at(0));
    trails.update([_node(2, 50.01, at(10))], now: at(10));
    // Same timestamp, different place (stale relay): not a new point.
    trails.update([_node(2, 50.02, at(10))], now: at(11));
    expect(trails.trails[2], hasLength(2));

    trails.update([_node(2, 50.03, at(35))], now: at(35));
    expect(trails.trails[2], const [LatLng(50.01, 14.0), LatLng(50.03, 14.0)]);
  });

  test('forgets nodes that left the list', () {
    final trails = PeerTrails();
    trails.update([_node(2, 50.0, at(0))], now: at(0));
    trails.update([_node(2, 50.01, at(1))], now: at(1));
    trails.update(const [], now: at(2));
    expect(trails.trails, isEmpty);
  });
}
