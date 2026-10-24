import 'dart:convert';

import 'package:http/http.dart' as http;

/// Base URL of the tactical backend (server/), set at build time with
/// `--dart-define=BACKEND_URL=https://ptt.example.cz/api`. Empty = demo
/// mode with local accounts and simulated PTT.
const backendUrlFromEnvironment = String.fromEnvironment('BACKEND_URL');

class BackendException implements Exception {
  const BackendException(this.statusCode, this.code, {this.retryAfter});

  /// HTTP status, 0 when the server could not be reached.
  final int statusCode;
  final String code;
  final Duration? retryAfter;

  @override
  String toString() => 'BackendException($statusCode, $code)';
}

class BackendUser {
  const BackendUser({
    required this.userName,
    required this.displayName,
    required this.role,
    required this.groups,
  });

  final String userName;
  final String displayName;
  final String role;
  final Set<String> groups;
}

class BackendLogin {
  const BackendLogin({required this.sessionToken, required this.user});

  final String sessionToken;
  final BackendUser user;
}

class GroupKeyMaterial {
  const GroupKeyMaterial({required this.id, required this.bytes});

  final int id;
  final List<int> bytes;
}

/// Everything needed to join a group's PTT room.
class PttJoinInfo {
  const PttJoinInfo({
    required this.liveKitUrl,
    required this.room,
    required this.identity,
    required this.token,
    required this.keys,
  });

  final String liveKitUrl;
  final String room;
  final String identity;
  final String token;

  /// Oldest first; the last one is the current sending key.
  final List<GroupKeyMaterial> keys;

  int get keyId => keys.last.id;
}

class BackendClient {
  BackendClient({required String baseUrl, http.Client? httpClient})
    : baseUri = Uri.parse(baseUrl.endsWith('/') ? baseUrl : '$baseUrl/'),
      _http = httpClient ?? http.Client();

  final Uri baseUri;
  final http.Client _http;

  Future<BackendLogin> login(
    String userName,
    String password, {
    String? deviceId,
    String? deviceName,
  }) async {
    final body = await _post(
      'auth/login',
      body: {
        'userName': userName,
        'password': password,
        'deviceId': ?deviceId,
        'deviceName': ?deviceName,
      },
    );
    final user = body['user'] as Map<String, dynamic>;
    return BackendLogin(
      sessionToken: body['sessionToken'] as String,
      user: BackendUser(
        userName: user['userName'] as String,
        displayName: user['displayName'] as String,
        role: user['role'] as String,
        groups: {for (final group in user['groups'] as List) '$group'},
      ),
    );
  }

  Future<PttJoinInfo> joinPtt(String sessionToken, String groupId) async {
    final body = await _post(
      'ptt/${Uri.encodeComponent(groupId)}/join',
      sessionToken: sessionToken,
    );
    GroupKeyMaterial key(Object? json) {
      final map = json as Map<String, dynamic>;
      return GroupKeyMaterial(
        id: map['id'] as int,
        bytes: base64Decode(map['key'] as String),
      );
    }

    return PttJoinInfo(
      liveKitUrl: body['livekitUrl'] as String,
      room: body['room'] as String,
      identity: body['identity'] as String,
      token: body['token'] as String,
      keys: [
        if (body['previousKey'] != null) key(body['previousKey']),
        key(body['key']),
      ],
    );
  }

  void close() => _http.close();

  Future<Map<String, dynamic>> _post(
    String path, {
    Object? body,
    String? sessionToken,
  }) async {
    final http.Response response;
    try {
      response = await _http
          .post(
            baseUri.resolve(path),
            headers: {
              'content-type': 'application/json',
              if (sessionToken != null) 'authorization': 'Bearer $sessionToken',
            },
            body: body == null ? null : jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      throw const BackendException(0, 'unreachable');
    }
    Map<String, dynamic> decoded;
    try {
      decoded = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      decoded = const {};
    }
    if (response.statusCode != 200) {
      final retry = decoded['retryAfterSeconds'];
      throw BackendException(
        response.statusCode,
        decoded['error']?.toString() ?? 'http_${response.statusCode}',
        retryAfter: retry is int ? Duration(seconds: retry) : null,
      );
    }
    return decoded;
  }
}
