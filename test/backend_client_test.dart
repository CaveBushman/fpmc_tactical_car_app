import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tactical_car_app/services/auth_service.dart';
import 'package:tactical_car_app/services/backend_client.dart';

void main() {
  late List<http.Request> requests;

  BackendClient client(http.Response Function(http.Request) respond) {
    requests = [];
    return BackendClient(
      baseUrl: 'https://ptt.example.test/api',
      httpClient: MockClient((request) async {
        requests.add(request);
        return respond(request);
      }),
    );
  }

  http.Response json(int status, Object body) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json'},
  );

  test('remote login maps the backend profile to a session', () async {
    final auth = RemoteAuthService(
      client(
        (_) => json(200, {
          'sessionToken': 'session-1',
          'user': {
            'userName': 'medic',
            'displayName': 'MEDIC',
            'role': 'medic',
            'groups': ['alpha', 'med'],
          },
        }),
      ),
    );

    final result = await auth.login(userName: ' medic ', password: 'pw');

    expect(result.ok, isTrue);
    expect(result.session!.sessionToken, 'session-1');
    expect(result.session!.isDemo, isFalse);
    expect(result.session!.allowedGroupIds, {'alpha', 'med'});
    expect(
      requests.single.url.toString(),
      'https://ptt.example.test/api/auth/login',
    );
    expect(jsonDecode(requests.single.body)['userName'], 'medic');
  });

  test('remote login explains failures', () async {
    Future<String?> error(http.Response response) async {
      final auth = RemoteAuthService(client((_) => response));
      return (await auth.login(userName: 'x', password: 'y')).errorMessage;
    }

    expect(
      await error(json(401, {'error': 'invalid_credentials'})),
      'Neplatné jméno nebo heslo.',
    );
    expect(
      await error(json(429, {'error': 'locked', 'retryAfterSeconds': 42})),
      contains('42 s'),
    );
    final unreachable = RemoteAuthService(
      BackendClient(
        baseUrl: 'https://ptt.example.test',
        httpClient: MockClient((_) async => throw http.ClientException('down')),
      ),
    );
    expect(
      (await unreachable.login(userName: 'x', password: 'y')).errorMessage,
      contains('nedostupný'),
    );
  });

  test('joinPtt sends the session and orders keys oldest first', () async {
    final backend = client(
      (_) => json(200, {
        'livekitUrl': 'wss://ptt.example.test',
        'room': 'ptt-alpha',
        'identity': 'operator',
        'token': 'lk',
        'key': {'id': 4, 'key': base64Encode(List.filled(32, 4))},
        'previousKey': {'id': 3, 'key': base64Encode(List.filled(32, 3))},
      }),
    );

    final info = await backend.joinPtt('session-1', 'alpha');

    expect(requests.single.headers['authorization'], 'Bearer session-1');
    expect(requests.single.url.path, '/api/ptt/alpha/join');
    expect(info.keys.map((key) => key.id), [3, 4]);
    expect(info.keyId, 4);
    expect(info.keys.last.bytes, List.filled(32, 4));
  });
}
