import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tactical_car_app/controllers/tactical_controller.dart';
import 'package:tactical_car_app/models/member_status.dart';
import 'package:tactical_car_app/models/messaging.dart';
import 'package:tactical_car_app/services/backend_client.dart';
import 'package:tactical_car_app/services/location_service.dart';
import 'package:tactical_car_app/services/mesh_packet_repository.dart';

import 'support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<Map<String, dynamic>> reports;
  late List<Map<String, dynamic>> hqMessages;
  late int reportStatus;
  late Duration offset;
  late FakeLocationService location;
  late TacticalController controller;

  setUp(() async {
    reports = [];
    hqMessages = [];
    reportStatus = 200;
    offset = Duration.zero;
    location = FakeLocationService();
    final backend = BackendClient(
      baseUrl: 'https://ptt.example.test',
      httpClient: MockClient((request) async {
        final path = request.url.path;
        if (path.endsWith('/auth/login')) {
          return http.Response(
            jsonEncode({
              'sessionToken': 'token-1',
              'expiresInSeconds': 43200,
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
        if (path.endsWith('/report')) {
          expect(request.headers['authorization'], 'Bearer token-1');
          reports.add(jsonDecode(request.body) as Map<String, dynamic>);
          return http.Response.bytes(
            utf8.encode(
              reportStatus == 200
                  ? jsonEncode({'ok': true, 'messages': hqMessages})
                  : '{"error":"x"}',
            ),
            reportStatus,
          );
        }
        return http.Response('{"error":"forbidden_group"}', 403);
      }),
    );
    controller = TacticalController(
      locationService: location,
      meshtasticBleService: FakeBleService(),
      meshPacketRepository: MeshPacketRepository(),
      backend: backend,
      voiceTransportFactory: FakeVoiceTransport.new,
      nativePtt: FakeNativePttBridge(),
      carBridge: FakeCarBridge(),
      clock: () => DateTime.now().add(offset),
      agingTick: const Duration(milliseconds: 20),
    );
    addTearDown(controller.dispose);
    await controller.login('operator', 'secret-pass');
  });

  Future<void> fix(double lat) async {
    location.emit(
      LocationFix(
        latitude: lat,
        longitude: 14.4,
        altitudeM: 240.6,
        accuracyM: 6,
        timestamp: DateTime.now(),
      ),
    );
    await pumpEventQueue();
  }

  test('reports at most every 2 minutes, status changes at once', () async {
    await fix(50.0);
    expect(reports, hasLength(1));
    expect(reports.single['lat'], 50.0);
    expect(reports.single['alt'], 241);
    expect(reports.single['accuracy'], 6);
    expect(reports.single, isNot(contains('status')));

    await fix(50.001); // 30 s later: too soon
    expect(reports, hasLength(1));

    await controller.setOwnStatus(MemberStatus.wounded);
    await pumpEventQueue();
    expect(reports, hasLength(2));
    expect(reports.last['status'], 'wounded');

    offset = const Duration(minutes: 3);
    await fix(50.002);
    expect(reports, hasLength(3));
  });

  test('battery saver reports every 5 minutes; failures retry', () async {
    controller.setBatterySaver(true);
    reportStatus = 503;
    await fix(50.0);
    expect(reports, hasLength(1));
    // The failed report does not count: the next fix tries again.
    reportStatus = 200;
    await fix(50.001);
    expect(reports, hasLength(2));

    offset = const Duration(minutes: 3);
    await fix(50.002);
    expect(reports, hasLength(2)); // within 5 minutes
    offset = const Duration(minutes: 6);
    await fix(50.003);
    expect(reports, hasLength(3));
  });

  test('a phone standing still keeps reporting its last fix', () async {
    await fix(50.0);
    expect(reports, hasLength(1));
    // No new fixes (GPS reports movement only), but time passes.
    offset = const Duration(minutes: 2, seconds: 5);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(reports, hasLength(2));
    expect(reports.last['lat'], 50.0);
  });

  test(
    'a real session starts without the sample team, messages or points',
    () async {
      expect(controller.peers, isEmpty);
      expect(controller.messages, isEmpty);
      expect(controller.waypoints, isEmpty);
      expect(controller.selfNode.callSign, 'OPERATOR');
      // No sample battery is reported as the member's.
      await fix(50.0);
      expect(reports.single, isNot(contains('battery')));
    },
  );

  test('panel messages arrive with the report, once each', () async {
    final at = DateTime.now().toUtc().toIso8601String();
    hqMessages = [
      {
        'id': 7,
        'groupId': 'alpha',
        'text': 'Přesun na RV-1',
        'priority': true,
        'author': 'VELITEL',
        'at': at,
      },
      {
        'id': 8,
        'groupId': 'command',
        'text': 'cizí skupina',
        'priority': false,
        'author': 'VELITEL',
        'at': at,
      },
    ];
    await fix(50.0);
    final message = controller.messages.first;
    expect(message.sender, TacticalController.hqSender);
    expect(message.body, 'Přesun na RV-1');
    expect(message.priority, isTrue);
    expect(message.groupId, 'alpha');
    expect(controller.messages.where((m) => m.body == 'cizí skupina'), isEmpty);
    expect(
      controller.missionEvents.first.text,
      'Zpráva z velitelství pro ALPHA: Přesun na RV-1',
    );

    // The next report asks only for newer ones; repeats are ignored.
    offset = const Duration(minutes: 3);
    await fix(50.001);
    expect(reports.last['sinceMessageId'], 8);
    expect(
      controller.messages.where((m) => m.body == 'Přesun na RV-1'),
      hasLength(1),
    );
  });

  test('"Rozumím" on a priority order reaches the server at once', () async {
    final at = DateTime.now().toUtc().toIso8601String();
    hqMessages = [
      {
        'id': 7,
        'groupId': 'alpha',
        'text': 'Stáhnout se',
        'priority': true,
        'author': 'VELITEL',
        'at': at,
      },
      {
        'id': 9,
        'groupId': 'alpha',
        'text': 'Jen informace',
        'priority': false,
        'author': 'VELITEL',
        'at': at,
      },
    ];
    await fix(50.0);
    hqMessages = [];
    final order = controller.messages.firstWhere((m) => m.hqMessageId == 7);
    final info = controller.messages.firstWhere((m) => m.hqMessageId == 9);
    expect(order.needsAcknowledgement, isTrue);
    expect(info.needsAcknowledgement, isFalse);

    // Offline first: the confirmation waits for a report that gets through.
    reportStatus = 503;
    controller.acknowledgeHqMessage(order);
    await pumpEventQueue();
    expect(reports.last['ackMessageIds'], [7]);
    final acknowledged = controller.messages.firstWhere(
      (m) => m.hqMessageId == 7,
    );
    expect(acknowledged.needsAcknowledgement, isFalse);
    expect(acknowledged.acknowledgedAt, isNotNull);
    expect(
      controller.missionEvents.first.text,
      'Potvrzen rozkaz velitelství: Stáhnout se',
    );

    reportStatus = 200;
    await fix(50.001);
    expect(reports.last['ackMessageIds'], [7]);
    offset = const Duration(minutes: 3);
    await fix(50.002);
    expect(reports.last, isNot(contains('ackMessageIds')));
    // A second tap does nothing.
    final count = reports.length;
    controller.acknowledgeHqMessage(acknowledged);
    await pumpEventQueue();
    expect(reports, hasLength(count));
  });

  test('acknowledgement survives a JSON round trip', () {
    final message = MeshMessage(
      sender: TacticalController.hqSender,
      body: 'Stáhnout se',
      sentAt: DateTime.utc(2026, 10, 26, 9),
      groupId: 'alpha',
      priority: true,
      viaInternet: true,
      hqMessageId: 7,
      acknowledgedAt: DateTime.utc(2026, 10, 26, 9, 5),
    );
    final restored = MeshMessage.fromJson(message.toJson());
    expect(restored.hqMessageId, 7);
    expect(restored.acknowledgedAt, DateTime.utc(2026, 10, 26, 9, 5));
    expect(restored.needsAcknowledgement, isFalse);
    expect(
      MeshMessage.fromJson(
        {...message.toJson()}..remove('acknowledgedAt'),
      ).needsAcknowledgement,
      isTrue,
    );
  });
}
