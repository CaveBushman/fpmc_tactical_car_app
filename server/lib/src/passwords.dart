import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// PBKDF2-HMAC-SHA256 password hashes stored as
/// `pbkdf2-sha256$<iterations>$<salt b64>$<hash b64>`.
class PasswordHasher {
  const PasswordHasher({this.iterations = 120000});

  final int iterations;

  String hash(String password, {List<int>? salt}) {
    final random = Random.secure();
    final saltBytes =
        salt ?? List<int>.generate(16, (_) => random.nextInt(256));
    final derived = _pbkdf2(utf8.encode(password), saltBytes, iterations, 32);
    return 'pbkdf2-sha256\$$iterations\$${base64Encode(saltBytes)}\$${base64Encode(derived)}';
  }

  bool verify(String password, String encoded) {
    final parts = encoded.split(r'$');
    if (parts.length != 4 || parts[0] != 'pbkdf2-sha256') {
      return false;
    }
    final rounds = int.tryParse(parts[1]);
    if (rounds == null || rounds < 1) {
      return false;
    }
    final List<int> salt;
    final List<int> expected;
    try {
      salt = base64Decode(parts[2]);
      expected = base64Decode(parts[3]);
    } on FormatException {
      return false;
    }
    final actual = _pbkdf2(
      utf8.encode(password),
      salt,
      rounds,
      expected.length,
    );
    return constantTimeEquals(actual, expected);
  }

  static Uint8List _pbkdf2(
    List<int> password,
    List<int> salt,
    int rounds,
    int length,
  ) {
    final hmac = Hmac(sha256, password);
    final output = BytesBuilder();
    for (var block = 1; output.length < length; block++) {
      final blockIndex = [
        (block >> 24) & 0xff,
        (block >> 16) & 0xff,
        (block >> 8) & 0xff,
        block & 0xff,
      ];
      var u = hmac.convert([...salt, ...blockIndex]).bytes;
      final t = List<int>.from(u);
      for (var i = 1; i < rounds; i++) {
        u = hmac.convert(u).bytes;
        for (var j = 0; j < t.length; j++) {
          t[j] ^= u[j];
        }
      }
      output.add(t);
    }
    return Uint8List.fromList(output.takeBytes().sublist(0, length));
  }
}

bool constantTimeEquals(List<int> a, List<int> b) {
  if (a.length != b.length) {
    return false;
  }
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}
