import '../models/mission_event.dart';

/// The mission's notable events, newest first, capped at [capacity].
class MissionLog {
  MissionLog({this.capacity = 500});

  final int capacity;
  final List<MissionEvent> _events = [];

  List<MissionEvent> get events => List.unmodifiable(_events);

  void add(MissionEvent event) {
    _events.insert(0, event);
    if (_events.length > capacity) {
      _events.removeLast();
    }
  }

  /// Appends events from a saved snapshot; they are older than anything
  /// logged since this login.
  void appendRestored(Iterable<MissionEvent> older) {
    _events.addAll(older.take(capacity - _events.length));
  }

  List<Map<String, dynamic>> toJson() => [
    for (final event in _events) event.toJson(),
  ];

  void clear() => _events.clear();
}
