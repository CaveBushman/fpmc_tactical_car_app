import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'audit_log.dart';
import 'group_keys.dart';
import 'livekit_tokens.dart';
import 'login_guard.dart';
import 'passwords.dart';
import 'sessions.dart';
import 'users.dart';

/// HTTP API used by the app:
///
/// - `POST /auth/login` `{userName, password}` → session token + profile
/// - `POST /ptt/<group>/join` (Bearer) → LiveKit URL/token + group E2EE keys
/// - `POST /admin/groups/<group>/rotate-key` (Bearer, commander)
/// - `GET /health`
class TacticalApi {
  TacticalApi({
    required this.users,
    required this.sessions,
    required this.liveKit,
    required this.liveKitUrl,
    required this.keys,
    required this.audit,
    LoginGuard? loginGuard,
    this.hasher = const PasswordHasher(),
  }) : loginGuard = loginGuard ?? LoginGuard();

  final UserDirectory users;
  final SessionIssuer sessions;
  final LiveKitTokenIssuer liveKit;
  final String liveKitUrl;
  final GroupKeyStore keys;
  final AuditLog audit;
  final LoginGuard loginGuard;
  final PasswordHasher hasher;

  // Verifying against a dummy hash keeps response time similar for unknown
  // users, so the API does not reveal which user names exist.
  late final String _dummyHash = hasher.hash('unused-dummy-password');

  Handler get handler {
    final router = Router()
      ..get('/health', (_) => _json(200, {'ok': true}))
      ..post('/auth/login', _login)
      ..post('/ptt/<group>/join', _joinPtt)
      ..post('/admin/groups/<group>/rotate-key', _rotateKey);
    return const Pipeline().addMiddleware(_noStore()).addHandler(router.call);
  }

  Future<Response> _login(Request request) async {
    final body = await _readJson(request);
    final userName = body?['userName']?.toString().trim().toLowerCase() ?? '';
    final password = body?['password']?.toString() ?? '';
    if (userName.isEmpty || password.isEmpty) {
      return _json(400, {'error': 'missing_credentials'});
    }

    final locked = loginGuard.lockedFor(userName);
    if (locked != null) {
      audit.record('login_locked', user: userName);
      return _json(429, {
        'error': 'locked',
        'retryAfterSeconds': locked.inSeconds + 1,
      });
    }

    final user = users.find(userName);
    final valid = hasher.verify(password, user?.passwordHash ?? _dummyHash);
    if (user == null || !valid) {
      loginGuard.recordFailure(userName);
      audit.record('login_failed', user: userName);
      return _json(401, {'error': 'invalid_credentials'});
    }

    loginGuard.recordSuccess(userName);
    audit.record('login', user: userName);
    return _json(200, {
      'sessionToken': sessions.issue(user.userName),
      'expiresInSeconds': sessions.lifetime.inSeconds,
      'user': user.toPublicJson(),
    });
  }

  Future<Response> _joinPtt(Request request, String group) async {
    final user = _authenticate(request);
    if (user == null) {
      return _json(401, {'error': 'unauthenticated'});
    }
    if (!user.groups.contains(group)) {
      audit.record(
        'ptt_denied',
        user: user.userName,
        details: {'group': group},
      );
      return _json(403, {'error': 'forbidden_group'});
    }
    final current = keys.current(group);
    final previous = keys.previous(group);
    audit.record(
      'ptt_join',
      user: user.userName,
      details: {'group': group, 'keyId': current.id},
    );
    return _json(200, {
      'livekitUrl': liveKitUrl,
      'room': 'ptt-$group',
      'identity': user.userName,
      'token': liveKit.issue(
        identity: user.userName,
        displayName: user.displayName,
        room: 'ptt-$group',
      ),
      'key': _keyJson(current),
      'previousKey': ?(previous == null ? null : _keyJson(previous)),
    });
  }

  Future<Response> _rotateKey(Request request, String group) async {
    final user = _authenticate(request);
    if (user == null) {
      return _json(401, {'error': 'unauthenticated'});
    }
    if (!user.isCommander) {
      audit.record(
        'rotate_denied',
        user: user.userName,
        details: {'group': group},
      );
      return _json(403, {'error': 'commander_only'});
    }
    final key = keys.rotate(group);
    audit.record(
      'key_rotated',
      user: user.userName,
      details: {'group': group, 'keyId': key.id},
    );
    return _json(200, {'group': group, 'keyId': key.id});
  }

  UserRecord? _authenticate(Request request) {
    final header = request.headers['authorization'] ?? '';
    if (!header.startsWith('Bearer ')) {
      return null;
    }
    final userName = sessions.verify(header.substring(7).trim());
    return userName == null ? null : users.find(userName);
  }

  Map<String, dynamic> _keyJson(GroupKey key) => {
    'id': key.id,
    'key': base64Encode(key.bytes),
  };

  static Future<Map<String, dynamic>?> _readJson(Request request) async {
    try {
      final decoded = jsonDecode(await request.readAsString());
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  static Response _json(int status, Object body) => Response(
    status,
    body: jsonEncode(body),
    headers: {'content-type': 'application/json'},
  );

  /// Tokens and keys must never end up in intermediary caches.
  static Middleware _noStore() =>
      (inner) => (request) async {
        final response = await inner(request);
        return response.change(headers: {'cache-control': 'no-store'});
      };
}
