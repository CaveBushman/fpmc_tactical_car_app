import '../models/mesh_node.dart';

/// Warns once when a radio's battery (own T-Beam or a teammate's) drops to
/// [lowPercent] or below; warns again only after it was back above
/// [rearmPercent] (charging), so values hovering at the edge stay quiet.
/// Readings above 100 mean external power and never warn.
class BatteryWatch {
  BatteryWatch({this.lowPercent = 20, this.rearmPercent = 30});

  final int lowPercent;
  final int rearmPercent;
  final Set<int> _warned = {};

  /// Nodes whose battery just went low.
  List<MeshNode> update(Iterable<MeshNode> nodes) {
    final low = <MeshNode>[];
    for (final node in nodes) {
      final percent = node.batteryPercent;
      if (percent == null || percent > 100) {
        continue;
      }
      if (percent <= lowPercent) {
        if (_warned.add(node.nodeNum)) {
          low.add(node);
        }
      } else if (percent > rearmPercent) {
        _warned.remove(node.nodeNum);
      }
    }
    return low;
  }

  void clear() => _warned.clear();
}
