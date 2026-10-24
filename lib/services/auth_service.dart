import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'backend_client.dart';
import 'device_identity.dart';

class AuthSession {
  const AuthSession({
    required this.userName,
    required this.displayName,
    required this.role,
    required this.allowedGroupIds,
    this.sessionToken,
    this.groupDefinitions = const [],
  });

  final String userName;
  final String displayName;
  final String role;
  final Set<String> allowedGroupIds;

  /// Backend session token; null for local demo accounts.
  final String? sessionToken;

  /// Group configuration from the backend; empty = built-in demo groups.
  final List<GroupDefinition> groupDefinitions;

  bool get isDemo => sessionToken == null;
}

class AuthResult {
  const AuthResult.success(this.session) : errorMessage = null;
  const AuthResult.failure(this.errorMessage) : session = null;

  final AuthSession? session;
  final String? errorMessage;

  bool get ok => session != null;
}

class AuthService {
  AuthService({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  static const maxFailedAttempts = 5;
  static const lockoutDuration = Duration(seconds: 30);
  static const _invalidCredentials = 'Neplatné jméno nebo heslo.';

  final DateTime Function() _clock;
  int _failedAttempts = 0;
  DateTime? _lockedUntil;

  Future<AuthResult> login({
    required String userName,
    required String password,
  }) async {
    final normalizedUser = userName.trim().toLowerCase();
    if (normalizedUser.isEmpty) {
      return const AuthResult.failure('Zadej uživatele.');
    }

    final lockedUntil = _lockedUntil;
    final now = _clock();
    if (lockedUntil != null && now.isBefore(lockedUntil)) {
      final seconds = lockedUntil.difference(now).inSeconds + 1;
      return AuthResult.failure('Příliš mnoho pokusů. Zkus to za $seconds s.');
    }

    final demoSession = _demoUsers[normalizedUser];
    final expectedHash = _demoPasswordHashes[normalizedUser];
    // Hash even for unknown users so the response does not reveal which
    // user names exist.
    final actualHash = _passwordHash(normalizedUser, password);
    if (demoSession == null ||
        expectedHash == null ||
        !_constantTimeEquals(actualHash, expectedHash)) {
      _failedAttempts++;
      if (_failedAttempts >= maxFailedAttempts) {
        _failedAttempts = 0;
        _lockedUntil = now.add(lockoutDuration);
      }
      return const AuthResult.failure(_invalidCredentials);
    }

    _failedAttempts = 0;
    _lockedUntil = null;
    return AuthResult.success(demoSession);
  }

  static String _passwordHash(String userName, String password) {
    final material = utf8.encode('1stpmc-demo:$userName:$password');
    return sha256.convert(material).toString();
  }

  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) {
      return false;
    }
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }

  Future<void> logout() async {}

  /// Local demo credentials only: SHA-256 of `1stpmc-demo:USER:PASSWORD`,
  /// where each demo password is `USER-2026`. Replace with
  /// server-backed authentication before real deployment.
  static const Map<String, String> _demoPasswordHashes = {
    'operator':
        '079245eb502a5f2ff2b199fc48ea7e98290b392f93e4404fe192d44345324a6f',
    'commander':
        '86ea987500d5cefd9868ced11006b63187932e630e6714fd6e96f3435e26ce53',
    'medic': 'e8f8259ba1f939972dcdd8539b06b342aa3ba5398f92d8f81176632184be5bfb',
  };

  static const Map<String, AuthSession> _demoUsers = {
    'operator': AuthSession(
      userName: 'operator',
      displayName: 'OPERATOR',
      role: 'operator',
      allowedGroupIds: {'alpha', 'bravo', 'med'},
    ),
    'commander': AuthSession(
      userName: 'commander',
      displayName: 'COMMANDER',
      role: 'commander',
      allowedGroupIds: {'alpha', 'bravo', 'med', 'command'},
    ),
    'medic': AuthSession(
      userName: 'medic',
      displayName: 'MEDIC',
      role: 'medic',
      allowedGroupIds: {'alpha', 'med'},
    ),
  };
}

/// Logs in against the tactical backend.
class RemoteAuthService extends AuthService {
  RemoteAuthService(this.backend, {this.device = const DeviceIdentity()});

  final BackendClient backend;
  final DeviceIdentity device;

  @override
  Future<AuthResult> login({
    required String userName,
    required String password,
  }) async {
    if (userName.trim().isEmpty) {
      return const AuthResult.failure('Zadej uživatele.');
    }
    try {
      final login = await backend.login(
        userName.trim(),
        password,
        deviceId: await device.id(),
        deviceName: device.name,
      );
      final user = login.user;
      return AuthResult.success(
        AuthSession(
          userName: user.userName,
          displayName: user.displayName,
          role: user.role,
          allowedGroupIds: user.groups,
          sessionToken: login.sessionToken,
          groupDefinitions: login.groups,
        ),
      );
    } on BackendException catch (error) {
      return AuthResult.failure(switch (error.statusCode) {
        0 => 'Server je nedostupný. Zkontroluj připojení.',
        401 => AuthService._invalidCredentials,
        403 when error.code == 'device_not_allowed' =>
          'Účet už je přihlášený na povoleném počtu zařízení. '
              'Požádej velitele o odpojení starého zařízení.',
        403 when error.code == 'account_disabled' => 'Účet je zablokovaný.',
        429 =>
          'Příliš mnoho pokusů. Zkus to za ${error.retryAfter?.inSeconds ?? 60} s.',
        _ => 'Přihlášení selhalo (${error.code}).',
      });
    }
  }
}
