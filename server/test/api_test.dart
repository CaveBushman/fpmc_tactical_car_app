import 'dart:convert';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:shelf/shelf.dart';
import 'package:tactical_server/tactical_server.dart';
import 'package:test/test.dart';

const _hasher = PasswordHasher(iterations: 1000);
const _sessionSecret = 'test-session-secret-0123456789abcdef';
const _liveKitSecret = 'livekit-test-secret';

void main() {
  late TacticalApi api;
  late Handler handler;
  late AuditLog audit;
  late DateTime now;

  setUp(() {
    now = DateTime(2026, 10, 24, 12);
    audit = AuditLog();
    api = TacticalApi(
      users: UserDirectory([
        UserRecord(
          userName: 'operator',
          displayName: 'OPERATOR',
          role: 'operator',
          groups: {'alpha', 'bravo'},
          passwordHash: _hasher.hash('operator-pass'),
        ),
        UserRecord(
          userName: 'commander',
          displayName: 'COMMANDER',
          role: 'commander',
          groups: {'alpha', 'command'},
          passwordHash: _hasher.hash('commander-pass'),
        ),
      ]),
      sessions: SessionIssuer(secret: _sessionSecret),
      liveKit: LiveKitTokenIssuer(apiKey: 'APIkey', apiSecret: _liveKitSecret),
      liveKitUrl: 'wss://ptt.example.test',
      keys: GroupKeyStore(),
      audit: audit,
      loginGuard: LoginGuard(clock: () => now),
      hasher: _hasher,
    );
    handler = api.handler;
  });

  Future<Response> post(String path, {Object? body, String? token}) async {
    return handler(
      Request(
        'POST',
        Uri.parse('http://localhost$path'),
        body: body == null ? '' : jsonEncode(body),
        headers: {'authorization': ?(token == null ? null : 'Bearer $token')},
      ),
    );
  }

  Future<Map<String, dynamic>> json(Response response) async =>
      jsonDecode(await response.readAsString()) as Map<String, dynamic>;

  Future<String> login(String user, String password) async {
    final response = await post(
      '/auth/login',
      body: {'userName': user, 'password': password},
    );
    expect(response.statusCode, 200);
    return (await json(response))['sessionToken'] as String;
  }

  test('password hashes verify and reject', () {
    final hash = _hasher.hash('secret-123');
    expect(_hasher.verify('secret-123', hash), isTrue);
    expect(_hasher.verify('secret-124', hash), isFalse);
    expect(_hasher.verify('secret-123', 'garbage'), isFalse);
    expect(_hasher.hash('a'), isNot(_hasher.hash('a')));
  });

  test('login returns session and profile', () async {
    final response = await post(
      '/auth/login',
      body: {'userName': 'Operator ', 'password': 'operator-pass'},
    );
    final body = await json(response);

    expect(response.statusCode, 200);
    expect(response.headers['cache-control'], 'no-store');
    expect(body['user']['groups'], ['alpha', 'bravo']);
    expect(body['sessionToken'], isA<String>());
    expect(audit.recent.last['event'], 'login');
  });

  test('wrong password and unknown user look the same', () async {
    final wrong = await post(
      '/auth/login',
      body: {'userName': 'operator', 'password': 'nope'},
    );
    final unknown = await post(
      '/auth/login',
      body: {'userName': 'ghost', 'password': 'nope'},
    );
    expect(wrong.statusCode, 401);
    expect(unknown.statusCode, 401);
    expect(await wrong.readAsString(), await unknown.readAsString());
  });

  test('locks out after repeated failures', () async {
    for (var i = 0; i < 5; i++) {
      await post(
        '/auth/login',
        body: {'userName': 'operator', 'password': 'x'},
      );
    }
    final locked = await post(
      '/auth/login',
      body: {'userName': 'operator', 'password': 'operator-pass'},
    );
    expect(locked.statusCode, 429);

    now = now.add(const Duration(minutes: 6));
    await login('operator', 'operator-pass');
  });

  test('join returns a LiveKit token scoped to the group room', () async {
    final session = await login('operator', 'operator-pass');

    final response = await post('/ptt/alpha/join', token: session);
    final body = await json(response);

    expect(response.statusCode, 200);
    expect(body['livekitUrl'], 'wss://ptt.example.test');
    expect(body['room'], 'ptt-alpha');
    final jwt = JWT.verify(body['token'] as String, SecretKey(_liveKitSecret));
    expect(jwt.issuer, 'APIkey');
    expect(jwt.subject, 'operator');
    final video = (jwt.payload as Map)['video'] as Map;
    expect(video['room'], 'ptt-alpha');
    expect(video['roomJoin'], isTrue);
    expect(video['canPublishSources'], ['microphone']);
    final key = base64Decode(body['key']['key'] as String);
    expect(key, hasLength(32));
    expect(body['key']['id'], 1);
    expect(body.containsKey('previousKey'), isFalse);
  });

  test('join is refused without session or outside allowed groups', () async {
    expect((await post('/ptt/alpha/join')).statusCode, 401);
    expect(
      (await post('/ptt/alpha/join', token: 'forged.token.value')).statusCode,
      401,
    );
    final session = await login('operator', 'operator-pass');
    expect((await post('/ptt/command/join', token: session)).statusCode, 403);
    expect(audit.recent.last['event'], 'ptt_denied');
  });

  test('a token signed with another secret is rejected', () async {
    final forged = SessionIssuer(
      secret: 'some-other-secret-0123456789abcdef',
    ).issue('commander');
    expect((await post('/ptt/alpha/join', token: forged)).statusCode, 401);
  });

  test(
    'members of a group get the same key; rotation keeps previous',
    () async {
      final operator = await login('operator', 'operator-pass');
      final commander = await login('commander', 'commander-pass');

      final a = await json(await post('/ptt/alpha/join', token: operator));
      final b = await json(await post('/ptt/alpha/join', token: commander));
      expect(a['key'], b['key']);

      expect(
        (await post(
          '/admin/groups/alpha/rotate-key',
          token: operator,
        )).statusCode,
        403,
      );
      final rotated = await post(
        '/admin/groups/alpha/rotate-key',
        token: commander,
      );
      expect(rotated.statusCode, 200);

      final after = await json(await post('/ptt/alpha/join', token: operator));
      expect(after['key']['id'], 2);
      expect(after['previousKey'], a['key']);
      expect(audit.recent.map((e) => e['event']), contains('key_rotated'));
    },
  );
}
