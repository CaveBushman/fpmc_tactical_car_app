import 'package:latlong2/latlong.dart';

import '../models/geo.dart' as geo;
import '../models/navigation.dart';

/// Own position is within the alert radius of a DANGER point.
class DangerWarning {
  const DangerWarning({
    required this.waypoint,
    required this.distanceM,
    required this.bearingDeg,
    required this.enteredAt,
  });

  final TacticalWaypoint waypoint;
  final double distanceM;
  final double bearingDeg;

  /// When this approach started; a new approach after leaving gets a new
  /// time (used to alert once per approach).
  final DateTime enteredAt;
}

/// Watches the distance to DANGER points. A point alerts when we come
/// within [alertRadiusM] and clears only beyond [clearRadiusM], so GPS
/// jitter at the edge does not flap. SOS points are skipped: those are
/// teammates to drive to.
class DangerProximity {
  DangerProximity({this.alertRadiusM = 300, this.clearRadiusM = 450})
    : assert(clearRadiusM >= alertRadiusM);

  final double alertRadiusM;
  final double clearRadiusM;

  final Map<String, DateTime> _inside = {};
  final Set<String> _dismissed = {};
  List<DangerWarning> _active = const [];

  /// Points we are close to and have not dismissed, nearest first.
  List<DangerWarning> get warnings => [
    for (final warning in _active)
      if (!_dismissed.contains(warning.waypoint.code)) warning,
  ];

  static bool watches(TacticalWaypoint waypoint) =>
      waypoint.type == TacticalWaypointType.danger &&
      !waypoint.code.startsWith('SOS-');

  /// Re-evaluates against [self]; returns the points entered just now.
  List<DangerWarning> update(
    LatLng self,
    Iterable<TacticalWaypoint> waypoints, {
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();
    final active = <DangerWarning>[];
    final entered = <DangerWarning>[];
    final seen = <String>{};
    for (final waypoint in waypoints.where(watches)) {
      final code = waypoint.code;
      final distanceM = geo.distanceKm(self, waypoint.latLng) * 1000;
      final wasInside = _inside.containsKey(code);
      final inside = distanceM <= (wasInside ? clearRadiusM : alertRadiusM);
      if (!inside) {
        continue;
      }
      seen.add(code);
      final enteredAt = _inside.putIfAbsent(code, () => at);
      final warning = DangerWarning(
        waypoint: waypoint,
        distanceM: distanceM,
        bearingDeg: geo.bearingDeg(self, waypoint.latLng),
        enteredAt: enteredAt,
      );
      active.add(warning);
      if (!wasInside) {
        entered.add(warning);
      }
    }
    // Left (or deleted): forget, so the next approach alerts again.
    _inside.removeWhere((code, _) => !seen.contains(code));
    _dismissed.removeWhere((code) => !seen.contains(code));
    active.sort((a, b) => a.distanceM.compareTo(b.distanceM));
    _active = active;
    return entered;
  }

  /// "Beru": hide until we leave and come back.
  void dismiss(String code) => _dismissed.add(code);

  void reset() {
    _inside.clear();
    _dismissed.clear();
    _active = const [];
  }
}
