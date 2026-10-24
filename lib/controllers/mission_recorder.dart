import '../models/geo.dart' as geo;
import '../models/messaging.dart';
import '../models/mission_event.dart';
import '../models/navigation.dart';
import '../models/track.dart';
import '../services/location_service.dart';
import '../services/mission_export.dart';

/// The own trail and the mission export (GPX + CSV via the share sheet).
class MissionRecorder {
  MissionRecorder({MissionSharer? sharer, this.maxPoints = 5000})
    : _sharer = sharer ?? MissionSharer.system();

  final MissionSharer _sharer;
  final int maxPoints;
  final List<TrackPoint> _track = [];

  /// Oldest first.
  List<TrackPoint> get track => List.unmodifiable(_track);

  /// Adds a point every 15 m, or once a minute when moving slowly.
  /// Returns whether the fix was recorded.
  bool record(LocationFix fix) {
    final point = TrackPoint(
      latitude: fix.latitude,
      longitude: fix.longitude,
      altitudeM: fix.altitudeM.round(),
      at: fix.timestamp,
    );
    final last = _track.lastOrNull;
    if (last != null &&
        geo.distanceKm(last.latLng, point.latLng) < 0.015 &&
        point.at.difference(last.at) < const Duration(minutes: 1)) {
      return false;
    }
    _track.add(point);
    if (_track.length > maxPoints) {
      _track.removeAt(0);
    }
    return true;
  }

  void clear() => _track.clear();

  void replace(Iterable<TrackPoint> points) {
    _track
      ..clear()
      ..addAll(points);
  }

  List<Map<String, dynamic>> toJson() => [
    for (final point in _track) point.toJson(),
  ];

  /// Shares GPX (waypoints + trail) and the CSV message log.
  Future<void> export({
    required String callSign,
    required List<TacticalWaypoint> waypoints,
    required List<MeshMessage> messages,
    required List<CommunicationGroup> groups,
    List<MissionEvent> events = const [],
    DateTime? now,
  }) async {
    final at = now ?? DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    final stamp =
        '${at.year}${two(at.month)}${two(at.day)}-${two(at.hour)}${two(at.minute)}';
    final name = 'Mise $callSign $stamp';
    await _sharer.share([
      ExportFile(
        name: 'mise-$stamp.gpx',
        mimeType: 'application/gpx+xml',
        content: buildMissionGpx(
          missionName: name,
          track: _track,
          waypoints: waypoints,
          exportedAt: at,
        ),
      ),
      ExportFile(
        name: 'zpravy-$stamp.csv',
        mimeType: 'text/csv',
        content: buildMessagesCsv(messages: messages, groups: groups),
      ),
      ExportFile(
        name: 'udalosti-$stamp.csv',
        mimeType: 'text/csv',
        content: buildEventsCsv(events),
      ),
    ], subject: name);
  }
}
