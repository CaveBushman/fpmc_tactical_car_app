import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../theme.dart';
import 'geo.dart' as geo;
import 'mesh_node.dart';

enum TacticalNavTargetKind { team, rally, medevac, danger, observation, supply }

extension TacticalNavTargetKindStyle on TacticalNavTargetKind {
  String get label {
    return switch (this) {
      TacticalNavTargetKind.team => 'TEAM',
      TacticalNavTargetKind.rally => 'RALLY',
      TacticalNavTargetKind.medevac => 'MEDEVAC',
      TacticalNavTargetKind.danger => 'DANGER',
      TacticalNavTargetKind.observation => 'OBS',
      TacticalNavTargetKind.supply => 'SUPPLY',
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
    this.waypoint,
    this.priority = false,
  });

  final String label;
  final TacticalNavTargetKind kind;
  final IconData icon;
  final String mgrs;
  final double distanceKm;
  final double bearingDeg;
  final TacticalWaypoint? waypoint;
  final bool priority;

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

class TacticalWaypoint {
  const TacticalWaypoint({
    required this.code,
    required this.type,
    required this.latitude,
    required this.longitude,
    required this.note,
    this.priority = false,
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

  LatLng get latLng => LatLng(latitude, longitude);

  IconData get icon {
    return switch (type) {
      TacticalWaypointType.rally => Icons.flag_outlined,
      TacticalWaypointType.medevac => Icons.medical_services_outlined,
      TacticalWaypointType.danger => Icons.warning_amber_outlined,
      TacticalWaypointType.observation => Icons.visibility_outlined,
      TacticalWaypointType.supply => Icons.inventory_2_outlined,
    };
  }

  String get typeLabel {
    return switch (type) {
      TacticalWaypointType.rally => 'RALLY',
      TacticalWaypointType.medevac => 'MEDEVAC',
      TacticalWaypointType.danger => 'DANGER',
      TacticalWaypointType.observation => 'OBS',
      TacticalWaypointType.supply => 'SUPPLY',
    };
  }

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

enum TacticalWaypointType { rally, medevac, danger, observation, supply }
