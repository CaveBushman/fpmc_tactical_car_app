import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:tactical_server/tactical_server.dart';
import 'package:test/test.dart';

const _hasher = PasswordHasher(iterations: 1000);

void main() {
  late Handler handler;
  late GroupDirectory groups;

  UserRecord user(String name, String role, Set<String> memberOf) => UserRecord(
    userName: name,
    displayName: name.toUpperCase(),
    role: role,
    groups: memberOf,
    passwordHash: _hasher.hash('$name-password'),
  );

  setUp(() {
    groups = GroupDirectory(GroupRecord.defaults);
    handler = TacticalApi(
      users: UserDirectory([
        user('commander', 'commander', {'alpha', 'command'}),
        user('operator', 'operator', {'alpha', 'bravo'}),
      ]),
      groups: groups,
      sessions: SessionIssuer(secret: 'groups-test-secret-0123456789abcdef'),
      liveKit: LiveKitTokenIssuer(apiKey: 'k', apiSecret: 's'),
      liveKitUrl: 'wss://ptt.example.test',
      keys: GroupKeyStore(),
      audit: AuditLog(),
      hasher: _hasher,
    ).handler;
  });

  Future<(int, Map<String, dynamic>)> call(
    String method,
    String path, {
    Object? body,
    String? token,
  }) async {
    final response = await handler(
      Request(
        method,
        Uri.parse('http://localhost$path'),
        body: body == null ? '' : jsonEncode(body),
        headers: {'authorization': ?(token == null ? null : 'Bearer $token')},
      ),
    );
    final text = await response.readAsString();
    return (
      response.statusCode,
      text.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(text) as Map<String, dynamic>,
    );
  }

  Future<(String, Map<String, dynamic>)> login(String name) async {
    final (status, body) = await call(
      'POST',
      '/auth/login',
      body: {'userName': name, 'password': '$name-password'},
    );
    expect(status, 200);
    return (body['sessionToken'] as String, body);
  }

  test('login returns definitions of the user\'s groups only', () async {
    final (_, body) = await login('operator');
    final defs = (body['groups'] as List).cast<Map<String, dynamic>>();
    expect(defs.map((g) => g['id']), ['alpha', 'bravo']);
    expect(defs.last['channelIndex'], 1);
    expect(defs.last['pttEnabled'], isTrue);
  });

  test('commander creates, edits and deletes groups', () async {
    final (admin, _) = await login('commander');

    final (created, group) = await call(
      'POST',
      '/admin/groups',
      body: {
        'id': 'recon',
        'name': 'RECON',
        'channelIndex': 4,
        'pttEnabled': false,
      },
      token: admin,
    );
    expect(created, 201);
    expect(group['channelIndex'], 4);

    expect(
      (await call(
        'POST',
        '/admin/groups',
        body: {'id': 'recon'},
        token: admin,
      )).$1,
      409,
    );
    expect(
      (await call(
        'POST',
        '/admin/groups',
        body: {'id': 'X!'},
        token: admin,
      )).$1,
      400,
    );
    expect(
      (await call(
        'POST',
        '/admin/groups',
        body: {'id': 'bad', 'channelIndex': 9},
        token: admin,
      )).$1,
      400,
    );

    final (updated, edited) = await call(
      'PATCH',
      '/admin/groups/recon',
      body: {'name': 'PRŮZKUM', 'pttEnabled': true},
      token: admin,
    );
    expect(updated, 200);
    expect(edited['name'], 'PRŮZKUM');
    expect(edited['channelIndex'], 4);

    final (listed, list) = await call('GET', '/admin/groups', token: admin);
    expect(listed, 200);
    final alpha = (list['groups'] as List).firstWhere(
      (g) => g['id'] == 'alpha',
    );
    expect(alpha['members'], ['commander', 'operator']);

    expect((await call('DELETE', '/admin/groups/recon', token: admin)).$1, 200);
    expect(groups.find('recon'), isNull);
  });

  test('a group with members cannot be deleted', () async {
    final (admin, _) = await login('commander');
    final (status, body) = await call(
      'DELETE',
      '/admin/groups/bravo',
      token: admin,
    );
    expect(status, 409);
    expect(body['members'], ['operator']);
  });

  test('new groups can be assigned to users and joined', () async {
    final (admin, _) = await login('commander');
    await call(
      'POST',
      '/admin/groups',
      body: {'id': 'recon', 'name': 'RECON', 'channelIndex': 4},
      token: admin,
    );
    final (assigned, _) = await call(
      'PATCH',
      '/admin/users/operator',
      body: {
        'groups': ['alpha', 'recon'],
      },
      token: admin,
    );
    expect(assigned, 200);

    final (token, body) = await login('operator');
    expect((body['groups'] as List).map((g) => g['id']), ['alpha', 'recon']);
    expect((await call('POST', '/ptt/recon/join', token: token)).$1, 200);
    expect((await call('POST', '/ptt/bravo/join', token: token)).$1, 403);
  });

  test('PTT can be switched off per group', () async {
    final (admin, _) = await login('commander');
    await call(
      'PATCH',
      '/admin/groups/bravo',
      body: {'pttEnabled': false},
      token: admin,
    );

    final (token, _) = await login('operator');
    final (status, body) = await call('POST', '/ptt/bravo/join', token: token);
    expect(status, 403);
    expect(body['error'], 'ptt_disabled');
    expect((await call('POST', '/ptt/alpha/join', token: token)).$1, 200);
  });

  test('groups are persisted and seeded with defaults', () async {
    final dir = await Directory.systemTemp.createTemp('groups_test');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/groups.json');

    final first = GroupDirectory.load(file);
    expect(first.ids, {'alpha', 'bravo', 'med', 'command'});
    first.put(const GroupRecord(id: 'recon', name: 'RECON', channelIndex: 5));

    final reloaded = GroupDirectory.load(file);
    expect(reloaded.find('recon')?.channelIndex, 5);
  });

  test('JSON responses declare UTF-8 for Czech names', () async {
    final (admin, _) = await login('commander');
    await call(
      'PATCH',
      '/admin/groups/bravo',
      body: {'name': 'PRŮZKUM'},
      token: admin,
    );
    final response = await handler(
      Request(
        'GET',
        Uri.parse('http://localhost/admin/groups'),
        headers: {'authorization': 'Bearer $admin'},
      ),
    );
    expect(response.headers['content-type'], contains('charset=utf-8'));
    expect(await response.readAsString(), contains('PRŮZKUM'));
  });
}
