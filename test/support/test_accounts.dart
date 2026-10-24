import 'package:tactical_car_app/services/auth_service.dart';

/// Offline accounts for the test suite only (the app has none). Passwords
/// are `<user>-2026`.
final testAccounts = {
  for (final (user, role, groups) in const [
    ('operator', 'operator', {'alpha', 'bravo', 'med'}),
    ('commander', 'commander', {'alpha', 'bravo', 'med', 'command'}),
    ('medic', 'medic', {'alpha', 'med'}),
  ])
    user: OfflineAccount(
      session: AuthSession(
        userName: user,
        displayName: user.toUpperCase(),
        role: role,
        allowedGroupIds: groups,
      ),
      passwordHash: AuthService.offlineHash(user, '$user-2026'),
    ),
};
