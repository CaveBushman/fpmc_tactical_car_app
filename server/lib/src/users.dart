import 'dart:convert';
import 'dart:io';

class DeviceBinding {
  const DeviceBinding({
    required this.id,
    required this.name,
    required this.boundAt,
    required this.lastSeen,
  });

  final String id;
  final String name;
  final DateTime boundAt;
  final DateTime lastSeen;

  DeviceBinding seen(DateTime at) =>
      DeviceBinding(id: id, name: name, boundAt: boundAt, lastSeen: at);

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'boundAt': boundAt.toUtc().toIso8601String(),
    'lastSeen': lastSeen.toUtc().toIso8601String(),
  };

  static DeviceBinding fromJson(Map<String, dynamic> json) => DeviceBinding(
    id: json['id'] as String,
    name: json['name'] as String? ?? '',
    boundAt: DateTime.parse(json['boundAt'] as String),
    lastSeen: DateTime.parse(json['lastSeen'] as String),
  );
}

class UserRecord {
  const UserRecord({
    required this.userName,
    required this.displayName,
    required this.role,
    required this.groups,
    required this.passwordHash,
    this.disabled = false,
    this.sessionVersion = 1,
    this.devices = const [],
  });

  final String userName;
  final String displayName;
  final String role;
  final Set<String> groups;
  final String passwordHash;
  final bool disabled;

  /// Bumped to invalidate every session of this user at once.
  final int sessionVersion;
  final List<DeviceBinding> devices;

  bool get isCommander => role == 'commander';

  UserRecord copyWith({
    String? displayName,
    String? role,
    Set<String>? groups,
    String? passwordHash,
    bool? disabled,
    int? sessionVersion,
    List<DeviceBinding>? devices,
  }) => UserRecord(
    userName: userName,
    displayName: displayName ?? this.displayName,
    role: role ?? this.role,
    groups: groups ?? this.groups,
    passwordHash: passwordHash ?? this.passwordHash,
    disabled: disabled ?? this.disabled,
    sessionVersion: sessionVersion ?? this.sessionVersion,
    devices: devices ?? this.devices,
  );

  Map<String, dynamic> toPublicJson() => {
    'userName': userName,
    'displayName': displayName,
    'role': role,
    'groups': groups.toList()..sort(),
  };

  /// Admin view: profile plus account state, never the password hash.
  Map<String, dynamic> toAdminJson() => {
    ...toPublicJson(),
    'disabled': disabled,
    'devices': [for (final device in devices) device.toJson()],
  };

  Map<String, dynamic> toJson() => {
    ...toPublicJson(),
    'passwordHash': passwordHash,
    'disabled': disabled,
    'sessionVersion': sessionVersion,
    'devices': [for (final device in devices) device.toJson()],
  };

  static UserRecord fromJson(Map<String, dynamic> json) => UserRecord(
    userName: (json['userName'] as String).trim().toLowerCase(),
    displayName: json['displayName'] as String,
    role: json['role'] as String,
    groups: {for (final group in json['groups'] as List) group.toString()},
    passwordHash: json['passwordHash'] as String,
    disabled: json['disabled'] == true,
    sessionVersion: json['sessionVersion'] as int? ?? 1,
    devices: [
      for (final device in json['devices'] as List? ?? const [])
        DeviceBinding.fromJson(device as Map<String, dynamic>),
    ],
  );
}

/// Users and their account state. With a [file] every change is written
/// atomically; the first start seeds it from the static users file.
class UserDirectory {
  UserDirectory(Iterable<UserRecord> users, {this.file})
    : _users = {for (final user in users) user.userName: user};

  final File? file;
  final Map<String, UserRecord> _users;

  UserRecord? find(String userName) => _users[userName.trim().toLowerCase()];

  List<UserRecord> get all =>
      _users.values.toList()..sort((a, b) => a.userName.compareTo(b.userName));

  void put(UserRecord user) {
    _users[user.userName] = user;
    _save();
  }

  static UserDirectory fromFile(String path, {File? stateFile}) {
    final source = stateFile != null && stateFile.existsSync()
        ? stateFile
        : File(path);
    final decoded = jsonDecode(source.readAsStringSync());
    final users = (decoded['users'] as List).cast<Map<String, dynamic>>().map(
      UserRecord.fromJson,
    );
    final directory = UserDirectory(users, file: stateFile);
    directory._save();
    return directory;
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
        'users': [for (final user in all) user.toJson()],
      }),
    );
    tmp.renameSync(file.path);
  }
}
