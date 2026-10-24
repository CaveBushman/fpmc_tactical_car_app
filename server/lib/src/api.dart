import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'admin_page.dart';
import 'audit_log.dart';
import 'group_keys.dart';
import 'groups.dart';
import 'livekit_tokens.dart';
import 'login_guard.dart';
import 'passwords.dart';
import 'sessions.dart';
import 'users.dart';

/// HTTP API used by the app and the admin page:
///
/// - `POST /auth/login` `{userName, password, deviceId?, deviceName?}`
/// - `POST /auth/password` (Bearer) `{oldPassword, newPassword}`
/// - `POST /auth/refresh` (Bearer) → fresh token for a still valid session
/// - `POST /ptt/<group>/join` (Bearer) → LiveKit URL/token + group keys
/// - commander only (Bearer):
///   - `GET /admin/users`, `POST /admin/users`, `PATCH /admin/users/<u>`
///   - `POST /admin/users/<u>/password`, `POST /admin/users/<u>/revoke`
///   - `DELETE /admin/users/<u>/devices/<id>`
///   - `GET /admin/groups`, `POST /admin/groups`,
///     `PATCH /admin/groups/<id>`, `DELETE /admin/groups/<id>`
///   - `POST /admin/groups/<group>/rotate-key`
///   - `GET /admin/audit?limit=N`
/// - `GET /admin` – web administration page
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
    this.maxDevicesPerUser = 2,
    GroupDirectory? groups,
    this.knownRoles = const {'operator', 'commander', 'medic'},
    DateTime Function()? clock,
  }) : groups = groups ?? GroupDirectory(GroupRecord.defaults),
       loginGuard = loginGuard ?? LoginGuard(),
       _clock = clock ?? DateTime.now;

  static const minPasswordLength = 10;

  final UserDirectory users;
  final SessionIssuer sessions;
  final LiveKitTokenIssuer liveKit;
  final String liveKitUrl;
  final GroupKeyStore keys;
  final AuditLog audit;
  final LoginGuard loginGuard;
  final PasswordHasher hasher;

  /// 0 = unlimited. A login from a further device is refused until an admin
  /// unbinds one.
  final int maxDevicesPerUser;
  final GroupDirectory groups;
  final Set<String> knownRoles;
  final DateTime Function() _clock;

  // Verifying against a dummy hash keeps response time similar for unknown
  // users, so the API does not reveal which user names exist.
  late final String _dummyHash = hasher.hash('unused-dummy-password');

  Handler get handler {
    final router = Router()
      ..get('/health', (_) => _json(200, {'ok': true}))
      ..get('/admin', (_) => _adminPage())
      ..post('/auth/login', _login)
      ..post('/auth/password', _changeOwnPassword)
      ..post('/auth/refresh', _refreshSession)
      ..post('/ptt/<group>/join', _joinPtt)
      ..get('/admin/users', _listUsers)
      ..post('/admin/users', _createUser)
      ..patch('/admin/users/<user>', _updateUser)
      ..post('/admin/users/<user>/password', _setPassword)
      ..post('/admin/users/<user>/revoke', _revokeSessions)
      ..delete('/admin/users/<user>/devices/<device>', _unbindDevice)
      ..get('/admin/groups', _listGroups)
      ..post('/admin/groups', _createGroup)
      ..patch('/admin/groups/<group>', _updateGroup)
      ..delete('/admin/groups/<group>', _deleteGroup)
      ..post('/admin/groups/<group>/rotate-key', _rotateKey)
      ..get('/admin/audit', _readAudit);
    return const Pipeline().addMiddleware(_noStore()).addHandler(router.call);
  }

  // --- Auth ------------------------------------------------------------------

  Future<Response> _login(Request request) async {
    final body = await _readJson(request);
    final userName = body?['userName']?.toString().trim().toLowerCase() ?? '';
    final password = body?['password']?.toString() ?? '';
    final deviceId = body?['deviceId']?.toString().trim();
    final deviceName = body?['deviceName']?.toString().trim() ?? '';
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
    if (user.disabled) {
      audit.record('login_disabled', user: userName);
      return _json(403, {'error': 'account_disabled'});
    }

    var account = user;
    if (deviceId != null && deviceId.isNotEmpty) {
      final now = _clock();
      final known = user.devices.where((d) => d.id == deviceId).firstOrNull;
      if (known != null) {
        account = user.copyWith(
          devices: [
            for (final device in user.devices)
              device.id == deviceId ? device.seen(now) : device,
          ],
        );
      } else if (maxDevicesPerUser > 0 &&
          user.devices.length >= maxDevicesPerUser) {
        audit.record(
          'login_device_refused',
          user: userName,
          details: {'deviceName': deviceName},
        );
        return _json(403, {'error': 'device_not_allowed'});
      } else {
        account = user.copyWith(
          devices: [
            ...user.devices,
            DeviceBinding(
              id: deviceId,
              name: deviceName,
              boundAt: now,
              lastSeen: now,
            ),
          ],
        );
        audit.record(
          'device_bound',
          user: userName,
          details: {'deviceName': deviceName},
        );
      }
      users.put(account);
    }

    loginGuard.recordSuccess(userName);
    audit.record('login', user: userName);
    return _json(200, {
      'sessionToken': sessions.issue(
        account.userName,
        version: account.sessionVersion,
        deviceId: deviceId,
      ),
      'expiresInSeconds': sessions.lifetime.inSeconds,
      'user': account.toPublicJson(),
      'groups': _groupsFor(account),
    });
  }

  /// Extends a session that is still valid (same version and device), so a
  /// long operation does not hit the token lifetime. Revoked, blocked or
  /// unbound sessions cannot be refreshed.
  Response _refreshSession(Request request) {
    final user = _authenticate(request);
    if (user == null) {
      return _json(401, {'error': 'unauthenticated'});
    }
    audit.record('session_refreshed', user: user.userName);
    return _json(200, {
      'sessionToken': sessions.issue(
        user.userName,
        version: user.sessionVersion,
        deviceId: _claims(request)?.deviceId,
      ),
      'expiresInSeconds': sessions.lifetime.inSeconds,
    });
  }

  Future<Response> _changeOwnPassword(Request request) async {
    final user = _authenticate(request);
    if (user == null) {
      return _json(401, {'error': 'unauthenticated'});
    }
    final body = await _readJson(request);
    final oldPassword = body?['oldPassword']?.toString() ?? '';
    final newPassword = body?['newPassword']?.toString() ?? '';
    if (!hasher.verify(oldPassword, user.passwordHash)) {
      audit.record('password_change_failed', user: user.userName);
      return _json(403, {'error': 'invalid_credentials'});
    }
    if (newPassword.length < minPasswordLength) {
      return _json(400, {'error': 'weak_password'});
    }
    // A new version logs out all other sessions; return a fresh token.
    final updated = user.copyWith(
      passwordHash: hasher.hash(newPassword),
      sessionVersion: user.sessionVersion + 1,
    );
    users.put(updated);
    audit.record('password_changed', user: user.userName);
    return _json(200, {
      'sessionToken': sessions.issue(
        updated.userName,
        version: updated.sessionVersion,
        deviceId: _claims(request)?.deviceId,
      ),
    });
  }

  // --- PTT -------------------------------------------------------------------

  Future<Response> _joinPtt(Request request, String group) async {
    final user = _authenticate(request);
    if (user == null) {
      return _json(401, {'error': 'unauthenticated'});
    }
    final definition = groups.find(group);
    if (definition == null || !user.groups.contains(group)) {
      audit.record(
        'ptt_denied',
        user: user.userName,
        details: {'group': group},
      );
      return _json(403, {'error': 'forbidden_group'});
    }
    if (!definition.pttEnabled) {
      return _json(403, {'error': 'ptt_disabled'});
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

  // --- Admin -----------------------------------------------------------------

  Response _listUsers(Request request) {
    final admin = _authenticateAdmin(request);
    if (admin is Response) {
      return admin;
    }
    return _json(200, {
      'users': [for (final user in users.all) user.toAdminJson()],
      'groups': groups.ids.toList()..sort(),
      'groupDefinitions': [for (final group in groups.all) group.toJson()],
      'roles': knownRoles.toList()..sort(),
    });
  }

  Future<Response> _createUser(Request request) async {
    final admin = _authenticateAdmin(request);
    if (admin is Response) {
      return admin;
    }
    final body = await _readJson(request) ?? const {};
    final userName = body['userName']?.toString().trim().toLowerCase() ?? '';
    if (!RegExp(r'^[a-z0-9._-]{3,32}$').hasMatch(userName)) {
      return _json(400, {'error': 'invalid_user_name'});
    }
    if (users.find(userName) != null) {
      return _json(409, {'error': 'user_exists'});
    }
    final password = body['password']?.toString() ?? '';
    if (password.length < minPasswordLength) {
      return _json(400, {'error': 'weak_password'});
    }
    final profile = _profileFrom(body);
    if (profile is Response) {
      return profile;
    }
    final (displayName, role, groups) =
        profile as (String, String, Set<String>);
    final user = UserRecord(
      userName: userName,
      displayName: displayName.isEmpty ? userName.toUpperCase() : displayName,
      role: role,
      groups: groups,
      passwordHash: hasher.hash(password),
    );
    users.put(user);
    audit.record(
      'user_created',
      user: (admin as UserRecord).userName,
      details: {'target': userName, 'role': role, 'groups': groups.toList()},
    );
    return _json(201, user.toAdminJson());
  }

  Future<Response> _updateUser(Request request, String userName) async {
    final admin = _authenticateAdmin(request);
    if (admin is Response) {
      return admin;
    }
    final user = users.find(userName);
    if (user == null) {
      return _json(404, {'error': 'not_found'});
    }
    final body = await _readJson(request) ?? const {};
    final merged = {
      'displayName': body['displayName'] ?? user.displayName,
      'role': body['role'] ?? user.role,
      'groups': body['groups'] ?? user.groups.toList(),
    };
    final profile = _profileFrom(merged);
    if (profile is Response) {
      return profile;
    }
    final (displayName, role, groups) =
        profile as (String, String, Set<String>);
    final disabled = body.containsKey('disabled')
        ? body['disabled'] == true
        : user.disabled;
    if ((admin as UserRecord).userName == user.userName &&
        (disabled || role != 'commander')) {
      return _json(400, {'error': 'cannot_lock_out_self'});
    }
    final accessChanged =
        role != user.role ||
        disabled != user.disabled ||
        !_sameSet(groups, user.groups);
    final updated = user.copyWith(
      displayName: displayName,
      role: role,
      groups: groups,
      disabled: disabled,
      // Access changes take effect immediately: existing sessions end.
      sessionVersion: accessChanged
          ? user.sessionVersion + 1
          : user.sessionVersion,
    );
    users.put(updated);
    audit.record(
      'user_updated',
      user: admin.userName,
      details: {
        'target': user.userName,
        'role': role,
        'groups': groups.toList(),
        'disabled': disabled,
      },
    );
    return _json(200, updated.toAdminJson());
  }

  Future<Response> _setPassword(Request request, String userName) async {
    final admin = _authenticateAdmin(request);
    if (admin is Response) {
      return admin;
    }
    final user = users.find(userName);
    if (user == null) {
      return _json(404, {'error': 'not_found'});
    }
    final password = (await _readJson(request))?['password']?.toString() ?? '';
    if (password.length < minPasswordLength) {
      return _json(400, {'error': 'weak_password'});
    }
    users.put(
      user.copyWith(
        passwordHash: hasher.hash(password),
        sessionVersion: user.sessionVersion + 1,
      ),
    );
    audit.record(
      'password_reset',
      user: (admin as UserRecord).userName,
      details: {'target': user.userName},
    );
    return _json(200, {'ok': true});
  }

  Response _revokeSessions(Request request, String userName) {
    final admin = _authenticateAdmin(request);
    if (admin is Response) {
      return admin;
    }
    final user = users.find(userName);
    if (user == null) {
      return _json(404, {'error': 'not_found'});
    }
    users.put(user.copyWith(sessionVersion: user.sessionVersion + 1));
    audit.record(
      'sessions_revoked',
      user: (admin as UserRecord).userName,
      details: {'target': user.userName},
    );
    return _json(200, {'ok': true});
  }

  Response _unbindDevice(Request request, String userName, String deviceId) {
    final admin = _authenticateAdmin(request);
    if (admin is Response) {
      return admin;
    }
    final user = users.find(userName);
    if (user == null || !user.devices.any((d) => d.id == deviceId)) {
      return _json(404, {'error': 'not_found'});
    }
    users.put(
      user.copyWith(
        devices: [
          for (final device in user.devices)
            if (device.id != deviceId) device,
        ],
      ),
    );
    audit.record(
      'device_unbound',
      user: (admin as UserRecord).userName,
      details: {'target': user.userName},
    );
    return _json(200, {'ok': true});
  }

  Response _listGroups(Request request) {
    final admin = _authenticateAdmin(request);
    if (admin is Response) {
      return admin;
    }
    return _json(200, {
      'groups': [
        for (final group in groups.all)
          {
            ...group.toJson(),
            'members': [
              for (final user in users.all)
                if (user.groups.contains(group.id)) user.userName,
            ],
          },
      ],
    });
  }

  Future<Response> _createGroup(Request request) async {
    final admin = _authenticateAdmin(request);
    if (admin is Response) {
      return admin;
    }
    final body = await _readJson(request) ?? const {};
    final id = body['id']?.toString().trim().toLowerCase() ?? '';
    if (!RegExp(r'^[a-z0-9_-]{2,20}$').hasMatch(id)) {
      return _json(400, {'error': 'invalid_group_id'});
    }
    if (groups.find(id) != null) {
      return _json(409, {'error': 'group_exists'});
    }
    final group = _groupFrom(
      GroupRecord(id: id, name: id.toUpperCase(), channelIndex: 0),
      body,
    );
    if (group is Response) {
      return group;
    }
    groups.put(group as GroupRecord);
    audit.record(
      'group_created',
      user: (admin as UserRecord).userName,
      details: group.toJson(),
    );
    return _json(201, group.toJson());
  }

  Future<Response> _updateGroup(Request request, String id) async {
    final admin = _authenticateAdmin(request);
    if (admin is Response) {
      return admin;
    }
    final existing = groups.find(id);
    if (existing == null) {
      return _json(404, {'error': 'not_found'});
    }
    final group = _groupFrom(existing, await _readJson(request) ?? const {});
    if (group is Response) {
      return group;
    }
    groups.put(group as GroupRecord);
    audit.record(
      'group_updated',
      user: (admin as UserRecord).userName,
      details: group.toJson(),
    );
    return _json(200, group.toJson());
  }

  Response _deleteGroup(Request request, String id) {
    final admin = _authenticateAdmin(request);
    if (admin is Response) {
      return admin;
    }
    if (groups.find(id) == null) {
      return _json(404, {'error': 'not_found'});
    }
    // Members must be moved first so nobody silently loses access.
    final members = [
      for (final user in users.all)
        if (user.groups.contains(id)) user.userName,
    ];
    if (members.isNotEmpty) {
      return _json(409, {'error': 'group_in_use', 'members': members});
    }
    groups.remove(id);
    audit.record(
      'group_deleted',
      user: (admin as UserRecord).userName,
      details: {'group': id},
    );
    return _json(200, {'ok': true});
  }

  /// [base] with the fields of [body] applied and validated, or an error.
  Object _groupFrom(GroupRecord base, Map<String, dynamic> body) {
    final name = body['name']?.toString().trim() ?? base.name;
    if (name.isEmpty || name.length > 20) {
      return _json(400, {'error': 'invalid_name'});
    }
    final channel = body.containsKey('channelIndex')
        ? body['channelIndex']
        : base.channelIndex;
    if (channel is! int || channel < 0 || channel > 7) {
      return _json(400, {'error': 'invalid_channel'});
    }
    final description =
        body['description']?.toString().trim() ?? base.description;
    if (description.length > 80) {
      return _json(400, {'error': 'description_too_long'});
    }
    return base.copyWith(
      name: name,
      channelIndex: channel,
      pttEnabled: body.containsKey('pttEnabled')
          ? body['pttEnabled'] == true
          : base.pttEnabled,
      description: description,
    );
  }

  List<Map<String, dynamic>> _groupsFor(UserRecord user) => [
    for (final group in groups.all)
      if (user.groups.contains(group.id)) group.toJson(),
  ];

  Response _rotateKey(Request request, String group) {
    final admin = _authenticateAdmin(request);
    if (admin is Response) {
      return admin;
    }
    if (groups.find(group) == null) {
      return _json(404, {'error': 'not_found'});
    }
    final key = keys.rotate(group);
    audit.record(
      'key_rotated',
      user: (admin as UserRecord).userName,
      details: {'group': group, 'keyId': key.id},
    );
    return _json(200, {'group': group, 'keyId': key.id});
  }

  Response _readAudit(Request request) {
    final admin = _authenticateAdmin(request);
    if (admin is Response) {
      return admin;
    }
    final limit =
        int.tryParse(
          request.url.queryParameters['limit'] ?? '',
        )?.clamp(1, 500) ??
        100;
    final entries = audit.recent.reversed.take(limit).toList();
    return _json(200, {'entries': entries});
  }

  Response _adminPage() => Response.ok(
    adminPageHtml,
    headers: {
      'content-type': 'text/html; charset=utf-8',
      // Everything is inline and self-contained; nothing may be loaded
      // from elsewhere and the page may not be framed.
      'content-security-policy':
          "default-src 'none'; script-src 'unsafe-inline'; "
          "style-src 'unsafe-inline'; connect-src 'self'; "
          "frame-ancestors 'none'; base-uri 'none'; form-action 'none'",
      'x-content-type-options': 'nosniff',
      'referrer-policy': 'no-referrer',
    },
  );

  // --- Helpers ---------------------------------------------------------------

  SessionClaims? _claims(Request request) {
    final header = request.headers['authorization'] ?? '';
    if (!header.startsWith('Bearer ')) {
      return null;
    }
    return sessions.verify(header.substring(7).trim());
  }

  /// Valid session of an enabled user whose session version and bound
  /// device still match.
  UserRecord? _authenticate(Request request) {
    final claims = _claims(request);
    if (claims == null) {
      return null;
    }
    final user = users.find(claims.userName);
    if (user == null ||
        user.disabled ||
        user.sessionVersion != claims.version) {
      return null;
    }
    final deviceId = claims.deviceId;
    if (deviceId != null && !user.devices.any((d) => d.id == deviceId)) {
      return null;
    }
    return user;
  }

  /// The commander making the request, or an error [Response].
  Object _authenticateAdmin(Request request) {
    final user = _authenticate(request);
    if (user == null) {
      return _json(401, {'error': 'unauthenticated'});
    }
    if (!user.isCommander) {
      audit.record(
        'admin_denied',
        user: user.userName,
        details: {'path': request.url.path},
      );
      return _json(403, {'error': 'commander_only'});
    }
    return user;
  }

  /// Validated (displayName, role, groups) or an error [Response].
  Object _profileFrom(Map<String, dynamic> body) {
    final displayName = body['displayName']?.toString().trim() ?? '';
    final role = body['role']?.toString() ?? 'operator';
    if (!knownRoles.contains(role)) {
      return _json(400, {'error': 'unknown_role'});
    }
    final rawGroups = body['groups'];
    if (rawGroups is! List) {
      return _json(400, {'error': 'groups_required'});
    }
    final groupIds = {for (final group in rawGroups) group.toString()};
    if (!groupIds.every(groups.ids.contains)) {
      return _json(400, {'error': 'unknown_group'});
    }
    if (displayName.length > 40) {
      return _json(400, {'error': 'display_name_too_long'});
    }
    return (displayName, role, groupIds);
  }

  static bool _sameSet(Set<String> a, Set<String> b) =>
      a.length == b.length && a.containsAll(b);

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
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  /// Tokens and keys must never end up in intermediary caches.
  static Middleware _noStore() =>
      (inner) => (request) async {
        final response = await inner(request);
        return response.change(headers: {'cache-control': 'no-store'});
      };
}
