import '../models/mesh_node.dart';

/// A teammate who just went silent (link status LOST).
class LostContact {
  const LostContact({
    required this.nodeNum,
    required this.callSign,
    required this.lastSeenAt,
    required this.mgrs,
  });

  final int nodeNum;
  final String callSign;
  final DateTime lastSeenAt;

  /// Last known position.
  final String mgrs;
}

/// Raises an alert when a teammate heard during this session goes LOST;
/// it clears when they are heard again, are acknowledged or disappear.
/// Nodes already lost when first seen (old snapshot) never alert.
class ContactWatch {
  final Map<int, MeshNodeLinkStatus> _lastStatus = {};
  final Map<int, LostContact> _alerts = {};

  /// Most recently lost first.
  List<LostContact> get alerts =>
      _alerts.values.toList()
        ..sort((a, b) => b.lastSeenAt.compareTo(a.lastSeenAt));

  /// Re-evaluates the peers; returns the ones lost just now.
  List<LostContact> update(Iterable<MeshNode> nodes) {
    final lostNow = <LostContact>[];
    final present = <int>{};
    for (final node in nodes) {
      if (node.isSelf) {
        continue;
      }
      present.add(node.nodeNum);
      final status = node.linkStatus;
      final previous = _lastStatus[node.nodeNum];
      _lastStatus[node.nodeNum] = status;
      if (status != MeshNodeLinkStatus.lost) {
        _alerts.remove(node.nodeNum);
      } else if (previous != null && previous != MeshNodeLinkStatus.lost) {
        final lost = LostContact(
          nodeNum: node.nodeNum,
          callSign: node.callSign,
          lastSeenAt: node.lastSeenAt,
          mgrs: node.mgrs,
        );
        _alerts[node.nodeNum] = lost;
        lostNow.add(lost);
      }
    }
    _lastStatus.removeWhere((nodeNum, _) => !present.contains(nodeNum));
    _alerts.removeWhere((nodeNum, _) => !present.contains(nodeNum));
    return lostNow;
  }

  /// "Beru": hide until the teammate is heard and lost again.
  void acknowledge(int nodeNum) => _alerts.remove(nodeNum);

  void clear() {
    _lastStatus.clear();
    _alerts.clear();
  }
}
