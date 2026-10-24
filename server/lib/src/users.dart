import 'dart:convert';
import 'dart:io';

class UserRecord {
  const UserRecord({
    required this.userName,
    required this.displayName,
    required this.role,
    required this.groups,
    required this.passwordHash,
  });

  final String userName;
  final String displayName;
  final String role;
  final Set<String> groups;
  final String passwordHash;

  bool get isCommander => role == 'commander';

  Map<String, dynamic> toPublicJson() => {
    'userName': userName,
    'displayName': displayName,
    'role': role,
    'groups': groups.toList()..sort(),
  };

  static UserRecord fromJson(Map<String, dynamic> json) => UserRecord(
    userName: (json['userName'] as String).trim().toLowerCase(),
    displayName: json['displayName'] as String,
    role: json['role'] as String,
    groups: {for (final group in json['groups'] as List) group.toString()},
    passwordHash: json['passwordHash'] as String,
  );
}

class UserDirectory {
  UserDirectory(Iterable<UserRecord> users)
    : _users = {for (final user in users) user.userName: user};

  final Map<String, UserRecord> _users;

  UserRecord? find(String userName) => _users[userName.trim().toLowerCase()];

  static UserDirectory fromFile(String path) {
    final decoded = jsonDecode(File(path).readAsStringSync());
    final users = (decoded['users'] as List).cast<Map<String, dynamic>>().map(
      UserRecord.fromJson,
    );
    return UserDirectory(users);
  }
}
