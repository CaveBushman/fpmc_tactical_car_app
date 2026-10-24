import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';

const _issuer = 'fpmc-tactical';
const _audience = 'tactical-app';

class SessionClaims {
  const SessionClaims({
    required this.userName,
    required this.version,
    this.deviceId,
  });

  final String userName;

  /// Must match the user's current session version.
  final int version;
  final String? deviceId;
}

/// Signed session tokens handed to the app after login.
class SessionIssuer {
  SessionIssuer({
    required String secret,
    this.lifetime = const Duration(hours: 12),
  }) : _key = SecretKey(secret);

  final SecretKey _key;
  final Duration lifetime;

  String issue(String userName, {int version = 1, String? deviceId}) {
    return JWT(
      {'typ': 'session', 'ver': version, 'dev': ?deviceId},
      subject: userName,
      issuer: _issuer,
      audience: Audience.one(_audience),
    ).sign(_key, expiresIn: lifetime);
  }

  /// Claims of a valid, unexpired token signed by us; null otherwise.
  SessionClaims? verify(String token) {
    try {
      final jwt = JWT.verify(
        token,
        _key,
        issuer: _issuer,
        audience: Audience.one(_audience),
      );
      final payload = jwt.payload;
      final subject = jwt.subject;
      if (payload is! Map || payload['typ'] != 'session' || subject == null) {
        return null;
      }
      return SessionClaims(
        userName: subject,
        version: payload['ver'] as int? ?? 1,
        deviceId: payload['dev'] as String?,
      );
    } on JWTException {
      return null;
    }
  }
}
