import 'package:latlong2/latlong.dart';

import '../models/geo.dart' as geo;
import '../models/mesh_node.dart';

/// Recent positions of each teammate, so the map can show where they came
/// from. Fed with the current node list; keeps [window] of history and adds
/// a point only after [minStepM] of movement.
class PeerTrails {
  PeerTrails({this.window = const Duration(minutes: 30), this.minStepM = 10});

  final Duration window;
  final double minStepM;
  final Map<int, List<({LatLng at, DateTime time})>> _trails = {};

  /// Trails with at least two points, oldest point first.
  Map<int, List<LatLng>> get trails => {
    for (final entry in _trails.entries)
      if (entry.value.length > 1)
        entry.key: [for (final point in entry.value) point.at],
  };

  void update(Iterable<MeshNode> nodes, {DateTime? now}) {
    final cutoff = (now ?? DateTime.now()).subtract(window);
    final present = <int>{};
    for (final node in nodes) {
      if (node.isSelf) {
        continue;
      }
      present.add(node.nodeNum);
      final trail = _trails.putIfAbsent(node.nodeNum, () => []);
      final last = trail.lastOrNull;
      if (last == null ||
          (node.lastSeenAt.isAfter(last.time) &&
              geo.distanceKm(last.at, node.latLng) * 1000 >= minStepM)) {
        trail.add((at: node.latLng, time: node.lastSeenAt));
      }
      trail.removeWhere((point) => point.time.isBefore(cutoff));
    }
    _trails.removeWhere(
      (nodeNum, trail) => !present.contains(nodeNum) || trail.isEmpty,
    );
  }

  void clear() => _trails.clear();
}
