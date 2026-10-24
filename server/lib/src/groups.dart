import 'dart:convert';
import 'dart:io';

/// An operation group: who may talk together, on which Meshtastic channel.
class GroupRecord {
  const GroupRecord({
    required this.id,
    required this.name,
    required this.channelIndex,
    this.pttEnabled = true,
    this.description = '',
  });

  final String id;
  final String name;

  /// Meshtastic channel slot (0–7) the group's text traffic uses.
  final int channelIndex;
  final bool pttEnabled;
  final String description;

  GroupRecord copyWith({
    String? name,
    int? channelIndex,
    bool? pttEnabled,
    String? description,
  }) => GroupRecord(
    id: id,
    name: name ?? this.name,
    channelIndex: channelIndex ?? this.channelIndex,
    pttEnabled: pttEnabled ?? this.pttEnabled,
    description: description ?? this.description,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'channelIndex': channelIndex,
    'pttEnabled': pttEnabled,
    'description': description,
  };

  static GroupRecord fromJson(Map<String, dynamic> json) => GroupRecord(
    id: json['id'] as String,
    name: json['name'] as String,
    channelIndex: json['channelIndex'] as int,
    pttEnabled: json['pttEnabled'] != false,
    description: json['description'] as String? ?? '',
  );

  static const defaults = [
    GroupRecord(id: 'alpha', name: 'ALPHA', channelIndex: 0),
    GroupRecord(id: 'bravo', name: 'BRAVO', channelIndex: 1),
    GroupRecord(id: 'med', name: 'MED', channelIndex: 2),
    GroupRecord(id: 'command', name: 'COMMAND', channelIndex: 3),
  ];
}

/// Operation groups, persisted like the users (atomic JSON writes).
class GroupDirectory {
  GroupDirectory(Iterable<GroupRecord> groups, {this.file})
    : _groups = {for (final group in groups) group.id: group};

  final File? file;
  final Map<String, GroupRecord> _groups;

  GroupRecord? find(String id) => _groups[id];

  Set<String> get ids => _groups.keys.toSet();

  List<GroupRecord> get all => _groups.values.toList()
    ..sort(
      (a, b) => a.channelIndex != b.channelIndex
          ? a.channelIndex.compareTo(b.channelIndex)
          : a.id.compareTo(b.id),
    );

  void put(GroupRecord group) {
    _groups[group.id] = group;
    _save();
  }

  void remove(String id) {
    _groups.remove(id);
    _save();
  }

  /// Loads [stateFile] if present, otherwise starts from [GroupRecord.defaults].
  static GroupDirectory load(File stateFile) {
    if (!stateFile.existsSync()) {
      final directory = GroupDirectory(GroupRecord.defaults, file: stateFile);
      directory._save();
      return directory;
    }
    final decoded = jsonDecode(stateFile.readAsStringSync());
    return GroupDirectory([
      for (final group in decoded['groups'] as List)
        GroupRecord.fromJson(group as Map<String, dynamic>),
    ], file: stateFile);
  }

  void _save() {
    final file = this.file;
    if (file == null) {
      return;
    }
    file.parent.createSync(recursive: true);
    final tmp = File('${file.path}.tmp');
    tmp.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'groups': [for (final group in all) group.toJson()],
      }),
    );
    tmp.renameSync(file.path);
  }
}
