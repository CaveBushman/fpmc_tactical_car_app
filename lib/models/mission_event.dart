import 'package:flutter/material.dart';

/// What a mission log entry is about.
enum MissionEventKind {
  sos('SOS', Icons.sos),
  status('STAV', Icons.person_outline),
  contact('SPOJENÍ', Icons.portable_wifi_off),
  danger('NEBEZPEČÍ', Icons.dangerous_outlined),
  navigation('NAVIGACE', Icons.navigation_outlined),
  waypoint('BOD', Icons.place_outlined);

  const MissionEventKind(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// One line of the mission log, for the after-action review.
class MissionEvent {
  const MissionEvent({
    required this.at,
    required this.kind,
    required this.text,
  });

  final DateTime at;
  final MissionEventKind kind;
  final String text;

  Map<String, dynamic> toJson() => {
    'at': at.toUtc().toIso8601String(),
    'kind': kind.name,
    'text': text,
  };

  /// Null for entries this build cannot read.
  static MissionEvent? fromJson(Map<String, dynamic> json) {
    final at = DateTime.tryParse(json['at']?.toString() ?? '');
    final kind = MissionEventKind.values
        .where((kind) => kind.name == json['kind'])
        .firstOrNull;
    final text = json['text']?.toString();
    if (at == null || kind == null || text == null) {
      return null;
    }
    return MissionEvent(at: at.toLocal(), kind: kind, text: text);
  }
}
