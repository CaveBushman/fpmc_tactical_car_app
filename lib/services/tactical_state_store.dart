import 'dart:convert';
import 'dart:math' as math;

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PersistedTacticalState {
  const PersistedTacticalState({
    required this.nodes,
    required this.messages,
    required this.savedAt,
    this.waypoints,
    this.track,
    this.owner,
  });

  final List<Map<String, dynamic>> nodes;
  final List<Map<String, dynamic>> messages;

  /// Null for snapshots written before waypoints were persisted.
  final List<Map<String, dynamic>>? waypoints;

  /// Own trail; null for snapshots written before it was recorded.
  final List<Map<String, dynamic>>? track;
  final DateTime savedAt;

  /// User name of the session that wrote the snapshot (null for legacy).
  final String? owner;
}

/// Holds the AES-256 key that encrypts the persisted tactical state.
abstract class StateKeyStore {
  Future<List<int>?> readKey();
  Future<void> writeKey(List<int> key);
  Future<void> deleteKey();
}

/// Keeps the key in Android Keystore / iOS Keychain backed storage.
class SecureStateKeyStore implements StateKeyStore {
  const SecureStateKeyStore({this.keyName = 'tactical_state_key_v1'});

  final String keyName;

  static const _storage = FlutterSecureStorage();

  @override
  Future<List<int>?> readKey() async {
    final value = await _storage.read(key: keyName);
    return value == null ? null : base64Decode(value);
  }

  @override
  Future<void> writeKey(List<int> key) {
    return _storage.write(key: keyName, value: base64Encode(key));
  }

  @override
  Future<void> deleteKey() => _storage.delete(key: keyName);
}

class InMemoryStateKeyStore implements StateKeyStore {
  List<int>? key;

  @override
  Future<List<int>?> readKey() async => key;

  @override
  Future<void> writeKey(List<int> value) async => key = value;

  @override
  Future<void> deleteKey() async => key = null;
}

/// Persists nodes and messages encrypted with AES-GCM 256. Positions and
/// traffic are operationally sensitive, so they never hit shared
/// preferences in plaintext; [clear] also destroys the key.
class TacticalStateStore {
  const TacticalStateStore({
    this.key = 'tactical_state_v2',
    this.legacyKey = 'tactical_state_v1',
    this.keyStore,
  });

  final String key;

  /// Plaintext snapshot written by older builds; migrated and removed.
  final String legacyKey;
  final StateKeyStore? keyStore;

  StateKeyStore get _keys => keyStore ?? const SecureStateKeyStore();

  static final _cipher = AesGcm.with256bits();

  Future<PersistedTacticalState?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw != null && raw.isNotEmpty) {
      final clear = await _decrypt(raw);
      if (clear == null) {
        // Key lost or data tampered with: unreadable, so drop it.
        await prefs.remove(key);
        return null;
      }
      return _parse(clear);
    }

    final legacy = prefs.getString(legacyKey);
    if (legacy == null || legacy.isEmpty) {
      return null;
    }
    final state = _parse(legacy);
    if (state != null) {
      await save(
        nodes: state.nodes,
        messages: state.messages,
        waypoints: state.waypoints ?? const [],
        track: state.track ?? const [],
        owner: state.owner,
      );
    }
    await prefs.remove(legacyKey);
    return state;
  }

  Future<void> save({
    required List<Map<String, dynamic>> nodes,
    required List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>> waypoints = const [],
    List<Map<String, dynamic>> track = const [],
    String? owner,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final payload = {
      'version': 2,
      'owner': owner,
      'savedAt': DateTime.now().toUtc().toIso8601String(),
      'nodes': nodes,
      'messages': messages,
      'waypoints': waypoints,
      'track': track,
    };
    await prefs.setString(key, await _encrypt(jsonEncode(payload)));
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
    await prefs.remove(legacyKey);
    await _keys.deleteKey();
  }

  Future<String> _encrypt(String clear) async {
    final box = await _cipher.encrypt(
      utf8.encode(clear),
      secretKey: SecretKey(await _loadOrCreateKey()),
      aad: utf8.encode(key),
    );
    return base64Encode(box.concatenation());
  }

  Future<String?> _decrypt(String stored) async {
    final keyBytes = await _keys.readKey();
    if (keyBytes == null) {
      return null;
    }
    try {
      final box = SecretBox.fromConcatenation(
        base64Decode(stored),
        nonceLength: _cipher.nonceLength,
        macLength: _cipher.macAlgorithm.macLength,
      );
      final clear = await _cipher.decrypt(
        box,
        secretKey: SecretKey(keyBytes),
        aad: utf8.encode(key),
      );
      return utf8.decode(clear);
    } on SecretBoxAuthenticationError {
      return null;
    } on FormatException {
      return null;
    }
  }

  Future<List<int>> _loadOrCreateKey() async {
    final existing = await _keys.readKey();
    if (existing != null && existing.length == 32) {
      return existing;
    }
    final random = math.Random.secure();
    final created = List<int>.generate(32, (_) => random.nextInt(256));
    await _keys.writeKey(created);
    return created;
  }

  PersistedTacticalState? _parse(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      return null;
    }
    return PersistedTacticalState(
      nodes: _mapList(decoded['nodes']),
      messages: _mapList(decoded['messages']),
      waypoints: decoded.containsKey('waypoints')
          ? _mapList(decoded['waypoints'])
          : null,
      track: decoded.containsKey('track') ? _mapList(decoded['track']) : null,
      savedAt:
          DateTime.tryParse(decoded['savedAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      owner: decoded['owner']?.toString(),
    );
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
