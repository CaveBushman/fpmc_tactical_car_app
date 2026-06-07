import 'package:flutter_test/flutter_test.dart';
import 'package:tactical_car_app/services/auth_service.dart';

void main() {
  test('logs in demo operator with limited groups', () async {
    final auth = AuthService();

    final result = await auth.login(userName: 'operator', password: '');

    expect(result.ok, isTrue);
    expect(result.session?.displayName, 'OPERATOR');
    expect(result.session?.allowedGroupIds, containsAll(['alpha', 'bravo', 'med']));
    expect(result.session?.allowedGroupIds, isNot(contains('command')));
  });

  test('rejects unknown local user', () async {
    final auth = AuthService();

    final result = await auth.login(userName: 'unknown', password: '');

    expect(result.ok, isFalse);
    expect(result.errorMessage, isNotNull);
  });
}
