import 'package:latlong2/latlong.dart';

import 'geo.dart' as geo;

class MeshNode {
  MeshNode({
    required this.nodeNum,
    required this.callSign,
    required this.latitude,
    required this.longitude,
    required this.altitudeM,
    required this.lastSeenAt,
    this.batteryPercent,
    this.distanceKm = 0,
    this.bearingDeg = 0,
    this.isSelf = false,
  }) : mgrs = geo.formatMgrs(latitude, longitude);

  final int nodeNum;
  final String callSign;
  final double latitude;
  final double longitude;
  final int altitudeM;

  /// Always derived from [latitude]/[longitude] so it cannot drift.
  final String mgrs;

  /// 0–100 %, above 100 = external power, null = not reported yet.
  final int? batteryPercent;
  final DateTime lastSeenAt;

  /// Relative to the self node; derived state, recomputed whenever either
  /// position changes and never persisted.
  final double distanceKm;
  final double bearingDeg;
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

  /// Copy with distance and bearing measured from [self].
  MeshNode relativeTo(MeshNode self) {
    if (isSelf) {
      return copyWith(distanceKm: 0, bearingDeg: 0);
    }
    return copyWith(
      distanceKm: geo.distanceKm(self.latLng, latLng),
      bearingDeg: geo.bearingDeg(self.latLng, latLng),
    );
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
      'batteryPercent': batteryPercent,
      'lastSeenAt': lastSeenAt.toUtc().toIso8601String(),
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
      batteryPercent: (json['batteryPercent'] as num?)?.toInt(),
      // Snapshots without a timestamp are treated as long lost rather than
      // freshly heard.
      lastSeenAt:
          DateTime.tryParse(json['lastSeenAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      isSelf: json['isSelf'] == true,
    );
  }

  MeshNode copyWith({
    int? nodeNum,
    String? callSign,
    double? latitude,
    double? longitude,
    int? altitudeM,
    int? batteryPercent,
    DateTime? lastSeenAt,
    double? distanceKm,
    double? bearingDeg,
    bool? isSelf,
  }) {
    return MeshNode(
      nodeNum: nodeNum ?? this.nodeNum,
      callSign: callSign ?? this.callSign,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      altitudeM: altitudeM ?? this.altitudeM,
      batteryPercent: batteryPercent ?? this.batteryPercent,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      distanceKm: distanceKm ?? this.distanceKm,
      bearingDeg: bearingDeg ?? this.bearingDeg,
      isSelf: isSelf ?? this.isSelf,
    );
  }

  /// Recomputes distance/bearing of every node from the self node.
  static List<MeshNode> relativeToSelf(List<MeshNode> nodes) {
    final self = nodes.where((node) => node.isSelf).firstOrNull;
    if (self == null) {
      return nodes;
    }
    return [for (final node in nodes) node.relativeTo(self)];
  }

  static List<MeshNode> demoNodes(DateTime now) => relativeToSelf([
    MeshNode(
      nodeNum: 0xA1100001,
      callSign: 'RAVEN-1',
      latitude: 50.087451,
      longitude: 14.420671,
      altitudeM: 241,
      batteryPercent: 88,
      lastSeenAt: now,
      isSelf: true,
    ),
    MeshNode(
      nodeNum: 0xA1100002,
      callSign: 'RAVEN-2',
      latitude: 50.094220,
      longitude: 14.407812,
      altitudeM: 252,
      batteryPercent: 76,
      lastSeenAt: now.subtract(const Duration(minutes: 1)),
    ),
    MeshNode(
      nodeNum: 0xA1100003,
      callSign: 'SCOUT-3',
      latitude: 50.081312,
      longitude: 14.438220,
      altitudeM: 219,
      batteryPercent: 61,
      lastSeenAt: now.subtract(const Duration(minutes: 7)),
    ),
    MeshNode(
      nodeNum: 0xA1100004,
      callSign: 'MED-4',
      latitude: 50.079502,
      longitude: 14.411871,
      altitudeM: 236,
      batteryPercent: 22,
      lastSeenAt: now.subtract(const Duration(minutes: 18)),
    ),
  ]);
}

enum MeshNodeLinkStatus {
  ok('OK'),
  stale('STALE'),
  lost('LOST');

  const MeshNodeLinkStatus(this.label);

  final String label;
}

String _normalizeSearchText(String value) {
  return value
      .toLowerCase()
      .replaceAll('!', '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
