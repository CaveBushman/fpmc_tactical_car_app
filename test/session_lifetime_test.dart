import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tactical_car_app/controllers/ptt_controller.dart';
import 'package:tactical_car_app/controllers/tactical_controller.dart';
import 'package:tactical_car_app/models/messaging.dart';
import 'package:tactical_car_app/services/backend_client.dart';
import 'package:tactical_car_app/services/mesh_packet_repository.dart';

import 'support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<http.Request> requests;
  late int refreshStatus;
  late int joinStatus;
  late List<TacticalController> controllers;

  BackendClient backend() => BackendClient(
    baseUrl: 'https://ptt.example.test',
    httpClient: MockClient((request) async {
      requests.add(request);
      final path = request.url.path;
      if (path.endsWith('/auth/login')) {
        return http.Response(
          jsonEncode({
            'sessionToken': 'token-1',
            'expiresInSeconds': 0,
            'user': {
              'userName': 'operator',
              'displayName': 'OPERATOR',
              'role': 'operator',
              'groups': ['alpha'],
            },
          }),
          200,
        );
      }
      if (path.endsWith('/auth/refresh')) {
        return refreshStatus == 200
            ? http.Response(
                '{"sessionToken":"token-2","expiresInSeconds":3600}',
                200,
              )
            : http.Response('{"error":"unauthenticated"}', refreshStatus);
      }
      if (joinStatus != 200) {
        return http.Response('{"error":"unauthenticated"}', joinStatus);
      }
      return http.Response(
        '{"livekitUrl":"wss://x","room":"ptt-alpha","identity":"operator","token":"t","key":{"id":1,"key":"${'A' * 43}="}}',
        200,
      );
    }),
  );

  TacticalController build() {
    final controller = TacticalController(
      locationService: FakeLocationService(),
      meshtasticBleService: FakeBleService(),
      meshPacketRepository: MeshPacketRepository(),
      backend: backend(),
      voiceTransportFactory: FakeVoiceTransport.new,
      nativePtt: FakeNativePttBridge(),
      carBridge: FakeCarBridge(),
      minSessionRefreshDelay: const Duration(milliseconds: 20),
    );
    controllers.add(controller);
    return controller;
  }

  setUp(() {
    requests = [];
    refreshStatus = 200;
    joinStatus = 200;
    controllers = [];
  });

  tearDown(() {
    for (final controller in controllers) {
      controller.dispose();
    }
  });

  String? bearer(String pathSuffix) => requests
      .lastWhere((r) => r.url.path.endsWith(pathSuffix))
      .headers['authorization'];

  test('refreshes the session before it expires', () async {
    final controller = build();
    await controller.login('operator', 'pw');
    await Future<void>.delayed(const Duration(milliseconds: 80));

    expect(bearer('/auth/refresh'), 'Bearer token-1');
    await controller.reconnectPtt();
    expect(bearer('/join'), 'Bearer token-2');
    expect(controller.session, isNotNull);
  });

  test('a refused refresh ends the session but keeps the data', () async {
    final controller = build();
    final notices = <String>[];
    controller.notices.listen(notices.add);
    refreshStatus = 401;
    await controller.login('operator', 'pw');
    await controller.sendMeshText(
      const MeshMessageDraft(text: 'Uchovat', groupId: 'alpha'),
    );

    // The refresh fires after a short delay; wait for it without relying
    // on exact timing (the full suite runs under load).
    for (var i = 0; i < 100 && controller.session != null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }

    expect(controller.session, isNull);
    expect(notices.last, contains('Přihlas se znovu'));
    expect(controller.messages.any((m) => m.body == 'Uchovat'), isFalse);

    refreshStatus = 200;
    await controller.login('operator', 'pw');
    await pumpEventQueue(times: 50);
    expect(controller.messages.any((m) => m.body == 'Uchovat'), isTrue);
  });

  test('a network error retries later instead of logging out', () async {
    final controller = build();
    await controller.login('operator', 'pw');
    refreshStatus = 503;
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(controller.session, isNotNull);
  });

  test('PTT join refused with 401 ends the session', () async {
    joinStatus = 401;
    final controller = build();
    await controller.login('operator', 'pw');
    await pumpEventQueue(times: 50);

    expect(controller.session, isNull);
    expect(controller.ptt.status, PttStatus.offline);
  });
}
