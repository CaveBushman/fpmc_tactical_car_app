import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../theme.dart';
import 'geo.dart' as geo;
import 'mesh_node.dart';

enum TacticalNavTargetKind {
  team,
  rally,
  medevac,
  danger,
  observation,
  supply,
  point,
}

extension TacticalNavTargetKindStyle on TacticalNavTargetKind {
  String get label {
    return switch (this) {
      TacticalNavTargetKind.team => 'TEAM',
      TacticalNavTargetKind.rally => 'RALLY',
      TacticalNavTargetKind.medevac => 'MEDEVAC',
      TacticalNavTargetKind.danger => 'DANGER',
      TacticalNavTargetKind.observation => 'OBS',
      TacticalNavTargetKind.supply => 'SUPPLY',
      TacticalNavTargetKind.point => 'BOD',
    };
  }

  Color get color {
    return switch (this) {
      TacticalNavTargetKind.team => blueForce,
      TacticalNavTargetKind.rally => sand,
      TacticalNavTargetKind.medevac => dangerRed,
      TacticalNavTargetKind.danger => dangerRed,
      TacticalNavTargetKind.observation => signalAmber,
      TacticalNavTargetKind.supply => tacticalKhaki,
      TacticalNavTargetKind.point => Colors.white,
    };
  }
}

class TacticalNavSolution {
  const TacticalNavSolution({
    required this.label,
    required this.kind,
    required this.icon,
    required this.mgrs,
    required this.distanceKm,
    required this.bearingDeg,
    required this.position,
    this.waypoint,
    this.nodeNum,
    this.priority = false,
  });

  final String label;
  final TacticalNavTargetKind kind;
  final IconData icon;
  final String mgrs;
  final double distanceKm;
  final double bearingDeg;
  final TacticalWaypoint? waypoint;

  /// Set for a teammate target.
  final int? nodeNum;
  final LatLng position;
  final bool priority;

  /// The [NavTarget] that keeps pointing at this solution.
  NavTarget get target {
    final waypoint = this.waypoint;
    if (waypoint != null) {
      return NavTarget.waypoint(waypoint.code);
    }
    final nodeNum = this.nodeNum;
    if (nodeNum != null) {
      return NavTarget.node(nodeNum);
    }
    return NavTarget.point(position);
  }

  String get etaLabel {
    final minutes = (distanceKm / 5.0 * 60).round().clamp(1, 999);
    return '${minutes}m';
  }

  static List<TacticalNavSolution> fromMission({
    required MeshNode self,
    required List<MeshNode> nodes,
    required List<TacticalWaypoint> waypoints,
  }) {
    final solutions = [
      for (final node in nodes.where((node) => !node.isSelf))
        TacticalNavSolution(
          label: node.callSign,
          kind: TacticalNavTargetKind.team,
          icon: Icons.person_pin_circle_outlined,
          mgrs: node.mgrs,
          distanceKm: geo.distanceKm(self.latLng, node.latLng),
          bearingDeg: geo.bearingDeg(self.latLng, node.latLng),
          position: node.latLng,
          nodeNum: node.nodeNum,
          priority: node.linkStatus != MeshNodeLinkStatus.ok,
        ),
      for (final waypoint in waypoints)
        TacticalNavSolution(
          label: waypoint.code,
          kind: waypoint.navKind,
          icon: waypoint.icon,
          mgrs: waypoint.mgrs,
          distanceKm: geo.distanceKm(self.latLng, waypoint.latLng),
          bearingDeg: geo.bearingDeg(self.latLng, waypoint.latLng),
          position: waypoint.latLng,
          waypoint: waypoint,
          priority: waypoint.priority,
        ),
    ];
    solutions.sort((a, b) {
      if (a.priority != b.priority) {
        return a.priority ? -1 : 1;
      }
      return a.distanceKm.compareTo(b.distanceKm);
    });
    return solutions;
  }
}

/// What the user chose to navigate to: a teammate (follows them as they
/// move), a map point by code, or a fixed position.
class NavTarget {
  const NavTarget.node(int this.nodeNum) : waypointCode = null, point = null;
  const NavTarget.waypoint(String this.waypointCode)
    : nodeNum = null,
      point = null;
  const NavTarget.point(LatLng this.point)
    : nodeNum = null,
      waypointCode = null;

  final int? nodeNum;
  final String? waypointCode;
  final LatLng? point;

  /// Live solution from [self], or null once the teammate or point is gone.
  TacticalNavSolution? resolve({
    required MeshNode self,
    required List<MeshNode> nodes,
    required List<TacticalWaypoint> waypoints,
  }) {
    final point = this.point;
    if (point != null) {
      final mgrs = geo.formatMgrs(point.latitude, point.longitude);
      return TacticalNavSolution(
        label: 'BOD ${mgrs.split(' ').skip(2).join(' ')}',
        kind: TacticalNavTargetKind.point,
        icon: Icons.place_outlined,
        mgrs: mgrs,
        distanceKm: geo.distanceKm(self.latLng, point),
        bearingDeg: geo.bearingDeg(self.latLng, point),
        position: point,
      );
    }
    return TacticalNavSolution.fromMission(
      self: self,
      nodes: nodes,
      waypoints: waypoints,
    ).where(matches).firstOrNull;
  }

  bool matches(TacticalNavSolution solution) =>
      (nodeNum != null && solution.nodeNum == nodeNum) ||
      (waypointCode != null && solution.waypoint?.code == waypointCode);

  @override
  bool operator ==(Object other) =>
      other is NavTarget &&
      other.nodeNum == nodeNum &&
      other.waypointCode == waypointCode &&
      other.point == point;

  @override
  int get hashCode => Object.hash(nodeNum, waypointCode, point);
}

class TacticalWaypoint {
  const TacticalWaypoint({
    required this.code,
    required this.type,
    required this.latitude,
    required this.longitude,
    required this.note,
    this.priority = false,
    this.sharedBy,
    this.createdAt,
    this.meshWaypointId,
  });

  final String code;
  final TacticalWaypointType type;
  final double latitude;
  final double longitude;

  /// Derived from the coordinates so shared reports never disagree with
  /// the map position.
  String get mgrs => geo.formatMgrs(latitude, longitude);
  final String note;
  final bool priority;

  /// Callsign that shared it over the mesh; null = created on this device.
  final String? sharedBy;
  final DateTime? createdAt;

  /// Id of a native Meshtastic waypoint (WAYPOINT_APP), so updates and
  /// deletions from other clients replace the same point.
  final int? meshWaypointId;

  LatLng get latLng => LatLng(latitude, longitude);

  /// Human-readable share format; [parseShareText] reads it back.
  String get shareText =>
      'WP $code | $typeLabel | MGRS $mgrs | LAT ${latitude.toStringAsFixed(6)} | LON ${longitude.toStringAsFixed(6)} | $note';

  static final _sharePattern = RegExp(
    r'^WP (\S+) \| ([A-Z]+) \| MGRS [^|]+\| LAT (-?\d+(?:\.\d+)?) \| LON (-?\d+(?:\.\d+)?)(?: \| (.*))?$',
  );

  /// Parses a waypoint shared as text by this app; null for other messages.
  static TacticalWaypoint? parseShareText(
    String text, {
    String? sharedBy,
    DateTime? receivedAt,
  }) {
    final match = _sharePattern.firstMatch(text.trim());
    if (match == null) {
      return null;
    }
    final type = typeFromLabel(match.group(2)!);
    final latitude = double.tryParse(match.group(3)!);
    final longitude = double.tryParse(match.group(4)!);
    if (type == null ||
        latitude == null ||
        longitude == null ||
        latitude.abs() > 90 ||
        longitude.abs() > 180) {
      return null;
    }
    return TacticalWaypoint(
      code: match.group(1)!,
      type: type,
      latitude: latitude,
      longitude: longitude,
      note: match.group(5)?.trim() ?? '',
      priority:
          type == TacticalWaypointType.medevac ||
          type == TacticalWaypointType.danger,
      sharedBy: sharedBy,
      createdAt: receivedAt,
    );
  }

  static TacticalWaypointType? typeFromLabel(String label) {
    final normalized = label.trim().toUpperCase();
    for (final type in TacticalWaypointType.values) {
      if (type.label == normalized) {
        return type;
      }
    }
    return null;
  }

  Map<String, dynamic> toJson() {
    return {
      'code': code,
      'type': type.name,
      'latitude': latitude,
      'longitude': longitude,
      'note': note,
      'priority': priority,
      'sharedBy': sharedBy,
      'createdAt': createdAt?.toUtc().toIso8601String(),
      'meshWaypointId': meshWaypointId,
    };
  }

  static TacticalWaypoint fromJson(Map<String, dynamic> json) {
    return TacticalWaypoint(
      code: json['code']?.toString() ?? 'WP',
      type: TacticalWaypointType.values.firstWhere(
        (type) => type.name == json['type'],
        orElse: () => TacticalWaypointType.observation,
      ),
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      note: json['note']?.toString() ?? '',
      priority: json['priority'] == true,
      sharedBy: json['sharedBy']?.toString(),
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? ''),
      meshWaypointId: (json['meshWaypointId'] as num?)?.toInt(),
    );
  }

  IconData get icon {
    return switch (type) {
      TacticalWaypointType.rally => Icons.flag_outlined,
      TacticalWaypointType.medevac => Icons.medical_services_outlined,
      TacticalWaypointType.danger => Icons.warning_amber_outlined,
      TacticalWaypointType.observation => Icons.visibility_outlined,
      TacticalWaypointType.supply => Icons.inventory_2_outlined,
    };
  }

  String get typeLabel => type.label;

  TacticalNavTargetKind get navKind {
    return switch (type) {
      TacticalWaypointType.rally => TacticalNavTargetKind.rally,
      TacticalWaypointType.medevac => TacticalNavTargetKind.medevac,
      TacticalWaypointType.danger => TacticalNavTargetKind.danger,
      TacticalWaypointType.observation => TacticalNavTargetKind.observation,
      TacticalWaypointType.supply => TacticalNavTargetKind.supply,
    };
  }

  static const demoWaypoints = [
    TacticalWaypoint(
      code: 'RALLY-1',
      type: TacticalWaypointType.rally,
      latitude: 50.086138,
      longitude: 14.414208,
      note: 'primarni shromazdiste',
    ),
    TacticalWaypoint(
      code: 'MED-POINT',
      type: TacticalWaypointType.medevac,
      latitude: 50.083846,
      longitude: 14.427594,
      note: 'vyzvednuti zranenych',
      priority: true,
    ),
    TacticalWaypoint(
      code: 'OBS-2',
      type: TacticalWaypointType.observation,
      latitude: 50.091922,
      longitude: 14.432875,
      note: 'pozorovaci bod sever',
    ),
  ];
}

enum TacticalWaypointType {
  rally('RALLY'),
  medevac('MEDEVAC'),
  danger('DANGER'),
  observation('OBS'),
  supply('SUPPLY');

  const TacticalWaypointType(this.label);

  final String label;
}

/// User input from the waypoint editor.
class WaypointDraft {
  const WaypointDraft({
    required this.type,
    required this.latitude,
    required this.longitude,
    this.code = '',
    this.note = '',
    this.share = false,
    this.editing,
  });

  /// The existing point this draft changes; null for a new point.
  final TacticalWaypoint? editing;

  final TacticalWaypointType type;
  final double latitude;
  final double longitude;
  final String code;
  final String note;

  /// Also send it to the selected group right away.
  final bool share;
}
