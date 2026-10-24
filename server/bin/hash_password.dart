import 'dart:io';

import 'package:tactical_server/tactical_server.dart';

/// Prints a password hash for config/users.json:
/// `dart run bin/hash_password.dart` (reads the password from stdin).
void main() {
  stdout.write('Heslo: ');
  stdin.echoMode = false;
  final password = stdin.readLineSync() ?? '';
  stdin.echoMode = true;
  stdout.writeln();
  if (password.length < 10) {
    stderr.writeln('Heslo musí mít aspoň 10 znaků.');
    exit(64);
  }
  stdout.writeln(const PasswordHasher().hash(password));
}
