import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:tactical_server/tactical_server.dart';
import 'package:test/test.dart';

const _hasher = PasswordHasher(iterations: 1000);

void main() {
  late TacticalApi api;
  late Handler handler;
  late AuditLog audit;

  UserRecord user(String name, String role, Set<String> groups) => UserRecord(
    userName: name,
    displayName: name.toUpperCase(),
    role: role,
    groups: groups,
    passwordHash: _hasher.hash('$name-password'),
  );

  setUp(() {
    audit = AuditLog();
    api = TacticalApi(
      users: UserDirectory([
        user('commander', 'commander', {'alpha', 'command'}),
        user('operator', 'operator', {'alpha', 'bravo'}),
      ]),
      sessions: SessionIssuer(secret: 'admin-test-secret-0123456789abcdef'),
      liveKit: LiveKitTokenIssuer(apiKey: 'k', apiSecret: 's'),
      liveKitUrl: 'wss://ptt.example.test',
      keys: GroupKeyStore(),
      audit: audit,
      hasher: _hasher,
    );
    handler = api.handler;
  });

  Future<Response> call(
    String method,
    String path, {
    Object? body,
    String? token,
  }) async => handler(
    Request(
      method,
      Uri.parse('http://localhost$path'),
      body: body == null ? '' : jsonEncode(body),
      headers: {'authorization': ?(token == null ? null : 'Bearer $token')},
    ),
  );

  Future<Map<String, dynamic>> json(Response response) async =>
      jsonDecode(await response.readAsString()) as Map<String, dynamic>;

  Future<String> login(String name, {String? device, String? password}) async {
    final response = await call(
      'POST',
      '/auth/login',
      body: {
        'userName': name,
        'password': password ?? '$name-password',
        'deviceId': ?device,
        'deviceName': ?(device == null ? null : 'Phone $device'),
      },
    );
    final body = await response.readAsString();
    expect(response.statusCode, 200, reason: body);
    return (jsonDecode(body) as Map<String, dynamic>)['sessionToken'] as String;
  }

  Future<int> join(String token) async =>
      (await call('POST', '/ptt/alpha/join', token: token)).statusCode;

  test(
    'binds up to two devices, refuses a third until one is unbound',
    () async {
      final admin = await login('commander');
      final first = await login('operator', device: 'd1');
      await login('operator', device: 'd2');
      await login('operator', device: 'd1'); // known device is fine

      final third = await call(
        'POST',
        '/auth/login',
        body: {
          'userName': 'operator',
          'password': 'operator-password',
          'deviceId': 'd3',
        },
      );
      expect(third.statusCode, 403);
      expect((await json(third))['error'], 'device_not_allowed');

      final unbind = await call(
        'DELETE',
        '/admin/users/operator/devices/d1',
        token: admin,
      );
      expect(unbind.statusCode, 200);
      // The session of the unbound device stops working…
      expect(await join(first), 401);
      // …and a new device can be bound.
      await login('operator', device: 'd3');
    },
  );

  test('revoking sessions and disabling a user take effect at once', () async {
    final admin = await login('commander');
    final session = await login('operator');
    expect(await join(session), 200);

    await call('POST', '/admin/users/operator/revoke', token: admin);
    expect(await join(session), 401);

    final fresh = await login('operator');
    final disable = await call(
      'PATCH',
      '/admin/users/operator',
      body: {'disabled': true},
      token: admin,
    );
    expect(disable.statusCode, 200);
    expect(await join(fresh), 401);
    final refused = await call(
      'POST',
      '/auth/login',
      body: {'userName': 'operator', 'password': 'operator-password'},
    );
    expect(refused.statusCode, 403);
    expect((await json(refused))['error'], 'account_disabled');
  });

  test('changing groups logs the user out and limits PTT access', () async {
    final admin = await login('commander');
    final session = await login('operator');

    await call(
      'PATCH',
      '/admin/users/operator',
      body: {
        'groups': ['bravo'],
      },
      token: admin,
    );

    expect(await join(session), 401);
    final fresh = await login('operator');
    expect(await join(fresh), 403);
  });

  test('a user changes their own password', () async {
    final session = await login('operator');

    final wrongOld = await call(
      'POST',
      '/auth/password',
      body: {'oldPassword': 'nope', 'newPassword': 'brand-new-secret'},
      token: session,
    );
    expect(wrongOld.statusCode, 403);
    final weak = await call(
      'POST',
      '/auth/password',
      body: {'oldPassword': 'operator-password', 'newPassword': 'short'},
      token: session,
    );
    expect(weak.statusCode, 400);

    final changed = await call(
      'POST',
      '/auth/password',
      body: {
        'oldPassword': 'operator-password',
        'newPassword': 'brand-new-secret',
      },
      token: session,
    );
    expect(changed.statusCode, 200);
    final newToken = (await json(changed))['sessionToken'] as String;
    expect(await join(session), 401);
    expect(await join(newToken), 200);
    await login('operator', password: 'brand-new-secret');
  });

  test('commander creates and edits users; no hashes are exposed', () async {
    final admin = await login('commander');

    final created = await call(
      'POST',
      '/admin/users',
      body: {
        'userName': 'scout',
        'displayName': 'SCOUT',
        'role': 'operator',
        'groups': ['alpha'],
        'password': 'scout-secret-1',
      },
      token: admin,
    );
    expect(created.statusCode, 201);

    final duplicate = await call(
      'POST',
      '/admin/users',
      body: {
        'userName': 'scout',
        'role': 'operator',
        'groups': ['alpha'],
        'password': 'scout-secret-1',
      },
      token: admin,
    );
    expect(duplicate.statusCode, 409);

    final invalid = await call(
      'POST',
      '/admin/users',
      body: {
        'userName': 'x',
        'role': 'operator',
        'groups': ['nope'],
        'password': 'short',
      },
      token: admin,
    );
    expect(invalid.statusCode, 400);

    final list = await call('GET', '/admin/users', token: admin);
    final raw = await list.readAsString();
    expect(raw, isNot(contains('pbkdf2')));
    expect(raw, isNot(contains('passwordHash')));
    final users = (jsonDecode(raw)['users'] as List).cast<Map>();
    expect(users.map((u) => u['userName']), contains('scout'));

    await login('scout', password: 'scout-secret-1');

    final reset = await call(
      'POST',
      '/admin/users/scout/password',
      body: {'password': 'scout-secret-2'},
      token: admin,
    );
    expect(reset.statusCode, 200);
    await login('scout', password: 'scout-secret-2');
  });

  test('admin endpoints are commander-only and audited', () async {
    final operator = await login('operator');
    for (final (method, path) in [
      ('GET', '/admin/users'),
      ('POST', '/admin/users/commander/revoke'),
      ('GET', '/admin/audit'),
    ]) {
      final response = await call(method, path, token: operator);
      expect(response.statusCode, 403, reason: path);
    }
    expect((await call('GET', '/admin/users')).statusCode, 401);
    expect(audit.recent.last['event'], 'admin_denied');

    final admin = await login('commander');
    final log = await json(
      await call('GET', '/admin/audit?limit=3', token: admin),
    );
    expect((log['entries'] as List), hasLength(3));
    expect((log['entries'] as List).first['event'], 'login');
  });

  test('commander cannot lock themselves out', () async {
    final admin = await login('commander');
    for (final body in [
      {'disabled': true},
      {'role': 'operator'},
    ]) {
      final response = await call(
        'PATCH',
        '/admin/users/commander',
        body: body,
        token: admin,
      );
      expect(response.statusCode, 400, reason: '$body');
    }
  });

  test('admin page is served with a strict CSP', () async {
    final response = await call('GET', '/admin');
    expect(response.statusCode, 200);
    expect(response.headers['content-type'], contains('text/html'));
    expect(
      response.headers['content-security-policy'],
      contains("default-src 'none'"),
    );
    expect(
      response.headers['content-security-policy'],
      contains("frame-ancestors 'none'"),
    );
    final html = await response.readAsString();
    expect(html, isNot(contains('innerHTML')));
    expect(html, isNot(contains('localStorage')));
  });

  test('user changes are persisted and reloaded', () async {
    final dir = await Directory.systemTemp.createTemp('users_test');
    addTearDown(() => dir.delete(recursive: true));
    final seed = File('${dir.path}/seed.json')
      ..writeAsStringSync(
        jsonEncode({
          'users': [
            user('commander', 'commander', {'alpha'}).toJson(),
          ],
        }),
      );
    final state = File('${dir.path}/data/users.json');

    final first = UserDirectory.fromFile(seed.path, stateFile: state);
    first.put(user('medic', 'medic', {'alpha'}));

    final reloaded = UserDirectory.fromFile(seed.path, stateFile: state);
    expect(reloaded.find('medic'), isNotNull);
    expect(reloaded.find('commander'), isNotNull);
  });
}
