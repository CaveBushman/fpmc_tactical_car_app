import 'package:flutter_test/flutter_test.dart';
import 'package:tactical_car_app/services/auth_service.dart';
import 'package:tactical_car_app/services/ptt_access_service.dart';

void main() {
  test('derives a stable encrypted PTT channel key for authorized group', () {
    const service = PttAccessService();
    const session = AuthSession(
      userName: 'operator',
      displayName: 'OPERATOR',
      role: 'operator',
      allowedGroupIds: {'alpha'},
      pttToken: 'token',
    );

    final access = service.authorize(session: session, groupId: 'alpha');
    final sameAccess = service.authorize(session: session, groupId: 'alpha');

    expect(access.channel, 'ALPHA');
    expect(access.keyBytes.length, 32);
    expect(access.keyBytes, sameAccess.keyBytes);
  });

  test('rejects unauthorized PTT group', () {
    const service = PttAccessService();
    const session = AuthSession(
      userName: 'operator',
      displayName: 'OPERATOR',
      role: 'operator',
      allowedGroupIds: {'alpha'},
      pttToken: 'token',
    );

    expect(() => service.authorize(session: session, groupId: 'command'), throwsStateError);
  });
}
