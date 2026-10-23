import 'package:flutter_test/flutter_test.dart';
import 'package:tactical_car_app/services/auth_service.dart';

void main() {
  test('logs in demo operator with limited groups', () async {
    final auth = AuthService();

    final result = await auth.login(
      userName: 'operator',
      password: 'operator-2026',
    );

    expect(result.ok, isTrue);
    expect(result.session?.displayName, 'OPERATOR');
    expect(
      result.session?.allowedGroupIds,
      containsAll(['alpha', 'bravo', 'med']),
    );
    expect(result.session?.allowedGroupIds, isNot(contains('command')));
  });

  test('rejects unknown local user', () async {
    final auth = AuthService();

    final result = await auth.login(
      userName: 'unknown',
      password: 'unknown-2026',
    );

    expect(result.ok, isFalse);
    expect(result.errorMessage, isNotNull);
  });

  test('rejects wrong or empty password', () async {
    final auth = AuthService();

    for (final password in ['', 'operator', 'Operator-2026']) {
      final result = await auth.login(userName: 'operator', password: password);
      expect(result.ok, isFalse, reason: 'password "$password"');
      expect(result.errorMessage, 'Neplatné jméno nebo heslo.');
    }
  });

  test('unknown user gets the same error as a wrong password', () async {
    final auth = AuthService();

    final unknown = await auth.login(userName: 'ghost', password: 'x');
    final wrong = await auth.login(userName: 'operator', password: 'x');

    expect(unknown.errorMessage, wrong.errorMessage);
  });

  test('locks out after repeated failures', () async {
    var now = DateTime(2026, 10, 23, 12);
    final auth = AuthService(clock: () => now);

    for (var i = 0; i < AuthService.maxFailedAttempts; i++) {
      await auth.login(userName: 'operator', password: 'bad');
    }
    final locked = await auth.login(
      userName: 'operator',
      password: 'operator-2026',
    );
    expect(locked.ok, isFalse);
    expect(locked.errorMessage, contains('Příliš mnoho pokusů'));

    now = now.add(AuthService.lockoutDuration);
    final unlocked = await auth.login(
      userName: 'operator',
      password: 'operator-2026',
    );
    expect(unlocked.ok, isTrue);
  });
}
