import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:tactical_server/tactical_server.dart';
import 'package:test/test.dart';

const _hasher = PasswordHasher(iterations: 1000);

void main() {
  late Handler handler;
  late DateTime now;

  setUp(() {
    now = DateTime(2026, 10, 24, 12);
    handler = TacticalApi(
      users: UserDirectory([
        UserRecord(
          userName: 'commander',
          displayName: 'COMMANDER',
          role: 'commander',
          groups: {'alpha'},
          passwordHash: _hasher.hash('commander-password'),
        ),
      ]),
      sessions: SessionIssuer(secret: 'rate-test-secret-0123456789abcdef'),
      liveKit: LiveKitTokenIssuer(apiKey: 'k', apiSecret: 's'),
      liveKitUrl: 'wss://x',
      keys: GroupKeyStore(),
      audit: AuditLog(),
      hasher: _hasher,
      trustProxy: true,
      loginGuard: LoginGuard(clock: () => now),
      loginRateLimiter: RateLimiter(maxAttempts: 8, clock: () => now),
    ).handler;
  });

  Future<(int, Map<String, dynamic>)> login(String password, String ip) async {
    final response = await handler(
      Request(
        'POST',
        Uri.parse('http://localhost/auth/login'),
        body: jsonEncode({'userName': 'commander', 'password': password}),
        headers: {'x-forwarded-for': '$ip, 10.0.0.1'},
      ),
    );
    return (
      response.statusCode,
      jsonDecode(await response.readAsString()) as Map<String, dynamic>,
    );
  }

  test('failures from one address do not lock the account elsewhere', () async {
    for (var i = 0; i < 5; i++) {
      await login('wrong', '203.0.113.9');
    }
    expect((await login('commander-password', '203.0.113.9')).$1, 429);
    expect((await login('commander-password', '198.51.100.7')).$1, 200);
  });

  test('rate limiter slides its window per key', () {
    final limiter = RateLimiter(maxAttempts: 3, clock: () => now);
    expect(limiter.allow('a'), isTrue);
    expect(limiter.allow('a'), isTrue);
    expect(limiter.allow('a'), isTrue);
    expect(limiter.allow('a'), isFalse);
    expect(limiter.allow('b'), isTrue);
    now = now.add(const Duration(minutes: 11));
    expect(limiter.allow('a'), isTrue);
  });

  test('the login endpoint answers 429 with retry time', () async {
    for (var i = 0; i < 8; i++) {
      await login('wrong', '192.0.2.50');
    }
    final (status, body) = await login('commander-password', '192.0.2.50');
    expect(status, 429);
    expect(body['error'], 'rate_limited');
    expect(body['retryAfterSeconds'], greaterThan(0));
  });
}
