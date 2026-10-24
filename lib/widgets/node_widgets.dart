import 'package:flutter/material.dart';

import '../models/member_status.dart';
import '../models/mesh_node.dart';
import '../theme.dart';

class NodeStatusBadge extends StatelessWidget {
  const NodeStatusBadge({required this.status, super.key});

  final MeshNodeLinkStatus status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
      decoration: BoxDecoration(
        color: status.color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: status.color.withValues(alpha: 0.38)),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          color: status.color,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class NodeHealthSummary {
  const NodeHealthSummary({
    required this.ok,
    required this.stale,
    required this.lost,
  });

  final int ok;
  final int stale;
  final int lost;

  static NodeHealthSummary fromNodes(List<MeshNode> nodes) {
    var ok = 0;
    var stale = 0;
    var lost = 0;
    for (final node in nodes) {
      switch (node.linkStatus) {
        case MeshNodeLinkStatus.ok:
          ok++;
        case MeshNodeLinkStatus.stale:
          stale++;
        case MeshNodeLinkStatus.lost:
          lost++;
      }
    }
    return NodeHealthSummary(ok: ok, stale: stale, lost: lost);
  }
}

extension MeshNodeLinkStatusStyle on MeshNodeLinkStatus {
  Color get color {
    return switch (this) {
      MeshNodeLinkStatus.ok => blueForce,
      MeshNodeLinkStatus.stale => signalAmber,
      MeshNodeLinkStatus.lost => dangerRed,
    };
  }
}

class NodeCard extends StatelessWidget {
  const NodeCard({
    required this.node,
    this.onCheckIn,
    this.memberStatus,
    super.key,
  });

  final MeshNode node;
  final VoidCallback? onCheckIn;

  /// Last status the member reported about themselves.
  final MemberStatusReport? memberStatus;

  @override
  Widget build(BuildContext context) {
    final status = node.linkStatus;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: node.isSelf ? signalAmber : status.color,
              foregroundColor: Colors.black,
              child: Text(
                node.callSign.characters.first,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          node.callSign,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      if (node.viaInternet) ...[
                        const SizedBox(width: 6),
                        const Tooltip(
                          message: 'Pozice přes internet',
                          child: Icon(
                            Icons.cloud_outlined,
                            size: 16,
                            color: blueForce,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    node.mgrs,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      color: sand,
                      fontSize: 12,
                    ),
                  ),
                  if (memberStatus case final report?) ...[
                    const SizedBox(height: 4),
                    MemberStatusChip(report: report),
                  ],
                  const SizedBox(height: 2),
                  Text(
                    '${node.distanceKm.toStringAsFixed(1)} km | ${node.bearingDeg.toStringAsFixed(0)} deg | ${node.lastSeenMinutes} min',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.68),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                NodeStatusBadge(status: status),
                const SizedBox(height: 6),
                BatteryBadge(percent: node.batteryPercent),
                if (onCheckIn != null) ...[
                  const SizedBox(height: 6),
                  IconButton.filledTonal(
                    tooltip: 'CHECK-IN ${node.callSign}',
                    onPressed: onCheckIn,
                    style: IconButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: status.color.withValues(alpha: 0.28),
                      fixedSize: const Size(38, 34),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    icon: const Icon(Icons.mark_chat_unread_outlined, size: 18),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class BatteryBadge extends StatelessWidget {
  const BatteryBadge({required this.percent, super.key});

  /// Null = unknown, above 100 = external power (Meshtastic reports 101).
  final int? percent;

  @override
  Widget build(BuildContext context) {
    final value = percent;
    final (icon, label, color) = switch (value) {
      null => (Icons.battery_unknown, '--', Colors.white54),
      > 100 => (Icons.power, 'EXT', sand),
      < 25 => (Icons.battery_alert, '$value%', dangerRed),
      _ => (Icons.battery_5_bar, '$value%', sand),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

/// Reported member status with its age, e.g. "ZRANĚN · 4 min".
class MemberStatusChip extends StatelessWidget {
  const MemberStatusChip({required this.report, super.key});

  final MemberStatusReport report;

  @override
  Widget build(BuildContext context) {
    final status = report.status;
    final minutes = DateTime.now().difference(report.at).inMinutes;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: status.color.withValues(alpha: status.urgent ? 0.9 : 0.25),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: status.color),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(status.icon, size: 14, color: Colors.white),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              '${status.label} · ${minutes < 1 ? 'teď' : '$minutes min'}',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
