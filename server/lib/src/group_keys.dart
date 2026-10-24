import 'dart:convert';
import 'dart:io';
import 'dart:math';

class GroupKey {
  const GroupKey({
    required this.id,
    required this.bytes,
    required this.createdAt,
  });

  /// Monotonic per group; clients use it as the E2EE key index.
  final int id;
  final List<int> bytes;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'key': base64Encode(bytes),
    'createdAt': createdAt.toUtc().toIso8601String(),
  };

  static GroupKey fromJson(Map<String, dynamic> json) => GroupKey(
    id: json['id'] as int,
    bytes: base64Decode(json['key'] as String),
    createdAt: DateTime.parse(json['createdAt'] as String),
  );
}

/// Random 256-bit E2EE keys per group with rotation. The current and the
/// previous key are handed out so clients can still decrypt during a
/// rotation. Persisted to [file] when given.
class GroupKeyStore {
  GroupKeyStore({this.file, Random? random})
    : _random = random ?? Random.secure() {
    final file = this.file;
    if (file != null && file.existsSync()) {
      final decoded =
          jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      decoded.forEach((group, keys) {
        _keys[group] = [
          for (final key in keys as List)
            GroupKey.fromJson(key as Map<String, dynamic>),
        ];
      });
    }
  }

  static const _retained = 2;

  final File? file;
  final Random _random;
  final Map<String, List<GroupKey>> _keys = {};

  GroupKey current(String group) {
    final keys = _keys[group];
    if (keys == null || keys.isEmpty) {
      return rotate(group);
    }
    return keys.last;
  }

  GroupKey? previous(String group) {
    final keys = _keys[group];
    if (keys == null || keys.length < 2) {
      return null;
    }
    return keys[keys.length - 2];
  }

  GroupKey rotate(String group) {
    final keys = _keys.putIfAbsent(group, () => []);
    final key = GroupKey(
      id: keys.isEmpty ? 1 : keys.last.id + 1,
      bytes: List<int>.generate(32, (_) => _random.nextInt(256)),
      createdAt: DateTime.now().toUtc(),
    );
    keys.add(key);
    while (keys.length > _retained) {
      keys.removeAt(0);
    }
    _save();
    return key;
  }

  void _save() {
    final file = this.file;
    if (file == null) {
      return;
    }
    file.parent.createSync(recursive: true);
    final tmp = File('${file.path}.tmp');
    tmp.writeAsStringSync(
      jsonEncode({
        for (final entry in _keys.entries)
          entry.key: [for (final key in entry.value) key.toJson()],
      }),
    );
    tmp.renameSync(file.path);
  }
}
