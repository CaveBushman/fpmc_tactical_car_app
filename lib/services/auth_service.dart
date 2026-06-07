class AuthSession {
  const AuthSession({
    required this.userName,
    required this.displayName,
    required this.role,
    required this.allowedGroupIds,
    required this.pttToken,
  });

  final String userName;
  final String displayName;
  final String role;
  final Set<String> allowedGroupIds;
  final String pttToken;
}

class AuthResult {
  const AuthResult.success(this.session) : errorMessage = null;
  const AuthResult.failure(this.errorMessage) : session = null;

  final AuthSession? session;
  final String? errorMessage;

  bool get ok => session != null;
}

class AuthService {
  AuthService();

  Future<AuthResult> login({
    required String userName,
    required String password,
  }) async {
    final normalizedUser = userName.trim().toLowerCase();
    if (normalizedUser.isEmpty) {
      return const AuthResult.failure('Zadej uživatele.');
    }

    final demoSession = _demoUsers[normalizedUser];
    if (demoSession == null) {
      return const AuthResult.failure('Uživatel není v lokální demo databázi.');
    }

    return AuthResult.success(demoSession);
  }

  Future<void> logout() async {}

  static const Map<String, AuthSession> _demoUsers = {
    'operator': AuthSession(
      userName: 'operator',
      displayName: 'OPERATOR',
      role: 'operator',
      allowedGroupIds: {'alpha', 'bravo', 'med'},
      pttToken: 'demo-operator-ptt-token',
    ),
    'commander': AuthSession(
      userName: 'commander',
      displayName: 'COMMANDER',
      role: 'commander',
      allowedGroupIds: {'alpha', 'bravo', 'med', 'command'},
      pttToken: 'demo-commander-ptt-token',
    ),
    'medic': AuthSession(
      userName: 'medic',
      displayName: 'MEDIC',
      role: 'medic',
      allowedGroupIds: {'alpha', 'med'},
      pttToken: 'demo-medic-ptt-token',
    ),
  };
}
