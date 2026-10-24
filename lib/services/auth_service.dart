import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

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
    this.expiresIn,
  });

  final String userName;
  final String displayName;
  final String role;
  final Set<String> allowedGroupIds;

  /// Backend session token; null for local demo accounts.
  final String? sessionToken;

  /// Group configuration from the backend; empty = built-in demo groups.
  final List<GroupDefinition> groupDefinitions;

  /// Lifetime of [sessionToken] when it was issued.
  final Duration? expiresIn;

  AuthSession withToken(String token, Duration expiresIn) => AuthSession(
    userName: userName,
    displayName: displayName,
    role: role,
    allowedGroupIds: allowedGroupIds,
    sessionToken: token,
    groupDefinitions: groupDefinitions,
    expiresIn: expiresIn,
  );

  bool get isDemo => sessionToken == null;
}

class AuthResult {
  const AuthResult.success(this.session) : errorMessage = null;
  const AuthResult.failure(this.errorMessage) : session = null;

  final AuthSession? session;
  final String? errorMessage;

  bool get ok => session != null;
}

/// An account that can log in without a server (tests only; see
/// [AuthService.offlineAccounts]).
class OfflineAccount {
  const OfflineAccount({required this.session, required this.passwordHash});

  final AuthSession session;

  /// SHA-256 hex of `1stpmc-demo:USER:PASSWORD`.
  final String passwordHash;
}

/// Login without a backend. Release builds have no accounts here: they
/// must be built with BACKEND_URL and use [RemoteAuthService].
class AuthService {
  AuthService({
    DateTime Function()? clock,
    Map<String, OfflineAccount>? accounts,
  }) : _clock = clock ?? DateTime.now,
       _accounts = accounts ?? offlineAccounts;

  /// Accounts for builds without a server. Empty in the app; the test
  /// suite fills it with its own accounts.
  @visibleForTesting
  static Map<String, OfflineAccount> offlineAccounts = const {};

  static const noServerMessage =
      'Aplikace nemá nastavený server. Je potřeba ji sestavit s adresou '
      'serveru (BACKEND_URL).';

  /// SHA-256 used for [OfflineAccount.passwordHash].
  static String offlineHash(String userName, String password) =>
      _passwordHash(userName.trim().toLowerCase(), password);

  final Map<String, OfflineAccount> _accounts;

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
    if (_accounts.isEmpty) {
      return const AuthResult.failure(noServerMessage);
    }

    final lockedUntil = _lockedUntil;
    final now = _clock();
    if (lockedUntil != null && now.isBefore(lockedUntil)) {
      final seconds = lockedUntil.difference(now).inSeconds + 1;
      return AuthResult.failure('Příliš mnoho pokusů. Zkus to za $seconds s.');
    }

    final account = _accounts[normalizedUser];
    // Hash even for unknown users so the response does not reveal which
    // user names exist.
    final actualHash = _passwordHash(normalizedUser, password);
    if (account == null ||
        !_constantTimeEquals(actualHash, account.passwordHash)) {
      _failedAttempts++;
      if (_failedAttempts >= maxFailedAttempts) {
        _failedAttempts = 0;
        _lockedUntil = now.add(lockoutDuration);
      }
      return const AuthResult.failure(_invalidCredentials);
    }

    _failedAttempts = 0;
    _lockedUntil = null;
    return AuthResult.success(account.session);
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
          expiresIn: login.expiresIn,
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
