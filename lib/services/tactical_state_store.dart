import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class PersistedTacticalState {
  const PersistedTacticalState({
    required this.nodes,
    required this.messages,
    required this.savedAt,
  });

  final List<Map<String, dynamic>> nodes;
  final List<Map<String, dynamic>> messages;
  final DateTime savedAt;
}

class TacticalStateStore {
  const TacticalStateStore({this.key = 'tactical_state_v1'});

  final String key;

  Future<PersistedTacticalState?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) {
      return null;
    }

    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      return null;
    }

    return PersistedTacticalState(
      nodes: _mapList(decoded['nodes']),
      messages: _mapList(decoded['messages']),
      savedAt:
          DateTime.tryParse(decoded['savedAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  Future<void> save({
    required List<Map<String, dynamic>> nodes,
    required List<Map<String, dynamic>> messages,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final payload = {
      'version': 1,
      'savedAt': DateTime.now().toUtc().toIso8601String(),
      'nodes': nodes,
      'messages': messages,
    };
    await prefs.setString(key, jsonEncode(payload));
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
  }

  List<Map<String, dynamic>> _mapList(Object? value) {
    if (value is! List) {
      return const [];
    }
    return [
      for (final item in value)
        if (item is Map)
          item.map((key, value) => MapEntry(key.toString(), value)),
    ];
  }
}
