import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';

const _issuer = 'fpmc-tactical';
const _audience = 'tactical-app';

/// Signed session tokens handed to the app after login.
class SessionIssuer {
  SessionIssuer({
    required String secret,
    this.lifetime = const Duration(hours: 12),
  }) : _key = SecretKey(secret);

  final SecretKey _key;
  final Duration lifetime;

  String issue(String userName) {
    return JWT(
      {'typ': 'session'},
      subject: userName,
      issuer: _issuer,
      audience: Audience.one(_audience),
    ).sign(_key, expiresIn: lifetime);
  }

  /// User name of a valid session token, or null.
  String? verify(String token) {
    try {
      final jwt = JWT.verify(
        token,
        _key,
        issuer: _issuer,
        audience: Audience.one(_audience),
      );
      final payload = jwt.payload;
      if (payload is! Map || payload['typ'] != 'session') {
        return null;
      }
      return jwt.subject;
    } on JWTException {
      return null;
    }
  }
}
