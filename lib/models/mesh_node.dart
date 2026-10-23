import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../widgets/node_widgets.dart';

class MeshNode {
  const MeshNode({
    required this.nodeNum,
    required this.callSign,
    required this.latitude,
    required this.longitude,
    required this.altitudeM,
    required this.mgrs,
    required this.batteryPercent,
    required this.lastSeenAt,
    required this.distanceKm,
    required this.bearingDeg,
    required this.mapOffset,
    this.isSelf = false,
  });

  final int nodeNum;
  final String callSign;
  final double latitude;
  final double longitude;
  final int altitudeM;
  final String mgrs;
  final int batteryPercent;
  final DateTime lastSeenAt;
  final double distanceKm;
  final double bearingDeg;
  final Offset mapOffset;
  final bool isSelf;

  LatLng get latLng => LatLng(latitude, longitude);

  String get nodeNumHex =>
      nodeNum.toRadixString(16).padLeft(8, '0').toUpperCase();

  /// Whole minutes since the node was last heard, aged against wall clock so
  /// the link status degrades on its own when packets stop arriving.
  int get lastSeenMinutes {
    final minutes = DateTime.now().difference(lastSeenAt).inMinutes;
    return minutes < 0 ? 0 : minutes;
  }

  MeshNodeLinkStatus get linkStatus {
    if (isSelf || lastSeenMinutes <= 5) {
      return MeshNodeLinkStatus.ok;
    }
    if (lastSeenMinutes <= 15) {
      return MeshNodeLinkStatus.stale;
    }
    return MeshNodeLinkStatus.lost;
  }

  bool matchesSearch(String query) {
    final normalizedQuery = _normalizeSearchText(query);
    if (normalizedQuery.isEmpty) {
      return true;
    }
    final searchable = _normalizeSearchText(
      '$callSign $mgrs $nodeNumHex ${linkStatus.label} '
      '${distanceKm.toStringAsFixed(1)} ${bearingDeg.toStringAsFixed(0)} '
      '$lastSeenMinutes',
    );
    return searchable.contains(normalizedQuery);
  }

  Map<String, dynamic> toJson() {
    return {
      'nodeNum': nodeNum,
      'callSign': callSign,
      'latitude': latitude,
      'longitude': longitude,
      'altitudeM': altitudeM,
      'mgrs': mgrs,
      'batteryPercent': batteryPercent,
      'lastSeenAt': lastSeenAt.toUtc().toIso8601String(),
      'distanceKm': distanceKm,
      'bearingDeg': bearingDeg,
      'mapOffsetX': mapOffset.dx,
      'mapOffsetY': mapOffset.dy,
      'isSelf': isSelf,
    };
  }

  static MeshNode fromJson(Map<String, dynamic> json) {
    return MeshNode(
      nodeNum: (json['nodeNum'] as num).toInt(),
      callSign: json['callSign']?.toString() ?? 'UNKNOWN',
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      altitudeM: (json['altitudeM'] as num?)?.toInt() ?? 0,
      mgrs: json['mgrs']?.toString() ?? '',
      batteryPercent: (json['batteryPercent'] as num?)?.toInt() ?? 100,
      // Snapshots without a timestamp are treated as long lost rather than
      // freshly heard.
      lastSeenAt:
          DateTime.tryParse(json['lastSeenAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      distanceKm: (json['distanceKm'] as num?)?.toDouble() ?? 0,
      bearingDeg: (json['bearingDeg'] as num?)?.toDouble() ?? 0,
      mapOffset: Offset(
        (json['mapOffsetX'] as num?)?.toDouble() ?? 0,
        (json['mapOffsetY'] as num?)?.toDouble() ?? 0,
      ),
      isSelf: json['isSelf'] == true,
    );
  }

  MeshNode copyWith({
    int? nodeNum,
    String? callSign,
    double? latitude,
    double? longitude,
    int? altitudeM,
    String? mgrs,
    int? batteryPercent,
    DateTime? lastSeenAt,
    double? distanceKm,
    double? bearingDeg,
    Offset? mapOffset,
    bool? isSelf,
  }) {
    return MeshNode(
      nodeNum: nodeNum ?? this.nodeNum,
      callSign: callSign ?? this.callSign,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      altitudeM: altitudeM ?? this.altitudeM,
      mgrs: mgrs ?? this.mgrs,
      batteryPercent: batteryPercent ?? this.batteryPercent,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      distanceKm: distanceKm ?? this.distanceKm,
      bearingDeg: bearingDeg ?? this.bearingDeg,
      mapOffset: mapOffset ?? this.mapOffset,
      isSelf: isSelf ?? this.isSelf,
    );
  }

  static List<MeshNode> demoNodes(DateTime now) => [
    MeshNode(
      nodeNum: 0xA1100001,
      callSign: 'RAVEN-1',
      latitude: 50.087451,
      longitude: 14.420671,
      altitudeM: 241,
      mgrs: '33U VR 58470 48210',
      batteryPercent: 88,
      lastSeenAt: now.subtract(const Duration(minutes: 0)),
      distanceKm: 0,
      bearingDeg: 0,
      mapOffset: Offset.zero,
      isSelf: true,
    ),
    MeshNode(
      nodeNum: 0xA1100002,
      callSign: 'RAVEN-2',
      latitude: 50.094220,
      longitude: 14.407812,
      altitudeM: 252,
      mgrs: '33U VR 57541 48958',
      batteryPercent: 76,
      lastSeenAt: now.subtract(const Duration(minutes: 1)),
      distanceKm: 1.2,
      bearingDeg: 313,
      mapOffset: const Offset(-0.42, -0.31),
    ),
    MeshNode(
      nodeNum: 0xA1100003,
      callSign: 'SCOUT-3',
      latitude: 50.081312,
      longitude: 14.438220,
      altitudeM: 219,
      mgrs: '33U VR 59728 47517',
      batteryPercent: 61,
      lastSeenAt: now.subtract(const Duration(minutes: 7)),
      distanceKm: 1.5,
      bearingDeg: 119,
      mapOffset: const Offset(0.47, 0.34),
    ),
    MeshNode(
      nodeNum: 0xA1100004,
      callSign: 'MED-4',
      latitude: 50.079502,
      longitude: 14.411871,
      altitudeM: 236,
      mgrs: '33U VR 57821 47302',
      batteryPercent: 22,
      lastSeenAt: now.subtract(const Duration(minutes: 18)),
      distanceKm: 1.1,
      bearingDeg: 221,
      mapOffset: const Offset(-0.26, 0.41),
    ),
  ];
}

enum MeshNodeLinkStatus { ok, stale, lost }

String _normalizeSearchText(String value) {
  return value
      .toLowerCase()
      .replaceAll('!', '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

double radians(double degrees) => degrees * math.pi / 180;
