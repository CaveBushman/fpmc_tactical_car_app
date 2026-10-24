import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tactical_car_app/controllers/tactical_controller.dart';
import 'package:tactical_car_app/models/mesh_node.dart';
import 'package:tactical_car_app/models/messaging.dart';
import 'package:tactical_car_app/services/backend_client.dart';
import 'package:tactical_car_app/services/location_service.dart';
import 'package:tactical_car_app/services/mesh_packet_repository.dart';
import 'package:tactical_car_app/services/ptt/voice_transport.dart';

import 'support/fakes.dart';

BackendClient _backend() => BackendClient(
  baseUrl: 'https://ptt.example.test',
  httpClient: MockClient((request) async {
    if (request.url.path.endsWith('/auth/login')) {
      return http.Response(
        '{"sessionToken":"s","user":{"userName":"operator","displayName":"OPERATOR","role":"operator","groups":["alpha","bravo"]}}',
        200,
      );
    }
    return http.Response(
      '{"livekitUrl":"wss://x","room":"ptt-alpha","identity":"operator","token":"t","key":{"id":1,"key":"${'A' * 43}="}}',
      200,
    );
  }),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeLocationService location;
  late FakeBleService ble;
  late List<FakeVoiceTransport> rooms;
  late TacticalController controller;

  FakeVoiceTransport room() => rooms.last;

  setUp(() async {
    location = FakeLocationService();
    ble = FakeBleService();
    rooms = [];
    controller = TacticalController(
      locationService: location,
      meshtasticBleService: ble,
      meshPacketRepository: MeshPacketRepository(),
      backend: _backend(),
      voiceTransportFactory: () {
        final transport = FakeVoiceTransport();
        rooms.add(transport);
        return transport;
      },
      nativePtt: FakeNativePttBridge(),
      carBridge: FakeCarBridge(),
    );
    await controller.login('operator', 'pw');
    await pumpEventQueue();
  });

  tearDown(() => controller.dispose());

  List<Map<String, dynamic>> sent(String topic) => [
    for (final (t, message) in room().sentData)
      if (t == topic) message,
  ];

  LocationFix fix(double lat, double lon) => LocationFix(
    latitude: lat,
    longitude: lon,
    altitudeM: 230,
    accuracyM: 5,
    timestamp: DateTime.now(),
  );

  group('positions', () {
    test('announces own position when the room connects', () {
      final positions = sent(RoomTopic.position);
      expect(positions, hasLength(1));
      expect(positions.single['callSign'], controller.selfNode.callSign);
      expect(positions.single['nodeNum'], controller.selfNode.nodeNum);
    });

    test('throttles by time and distance', () async {
      location.emit(fix(50.08746, 14.42068)); // ~1 m
      await pumpEventQueue();
      expect(sent(RoomTopic.position), hasLength(1));

      location.emit(fix(50.0880, 14.4207)); // ~60 m
      await pumpEventQueue();
      expect(sent(RoomTopic.position), hasLength(2));
      expect(sent(RoomTopic.position).last['lat'], 50.0880);
    });

    test('adds members known only over the internet', () async {
      room().remoteData('medic', RoomTopic.position, {
        'callSign': 'DOC',
        'lat': 50.1,
        'lon': 14.5,
        'battery': 64,
        'at': DateTime.now().toUtc().toIso8601String(),
      });
      await pumpEventQueue();

      final doc = controller.peers.firstWhere((n) => n.callSign == 'DOC');
      expect(doc.viaInternet, isTrue);
      expect(doc.batteryPercent, 64);
      expect(doc.distanceKm, greaterThan(0));
      expect(doc.linkStatus, MeshNodeLinkStatus.ok);
    });

    test('merges with the LoRa node of the same radio', () async {
      final raven2 = controller.peers.firstWhere(
        (n) => n.callSign == 'RAVEN-2',
      );
      final before = controller.peers.length;

      room().remoteData('scout', RoomTopic.position, {
        'callSign': 'RAVEN-2',
        'nodeNum': raven2.nodeNum,
        'lat': 50.2,
        'lon': 14.3,
        'at': DateTime.now().toUtc().toIso8601String(),
      });
      await pumpEventQueue();

      expect(controller.peers.length, before);
      final merged = controller.peers.firstWhere(
        (n) => n.callSign == 'RAVEN-2',
      );
      expect(merged.latitude, 50.2);
      expect(merged.viaInternet, isTrue);
    });

    test('ignores stale, future, invalid and own positions', () async {
      final before = controller.peers.length;
      final now = DateTime.now().toUtc();
      for (final message in [
        {
          'lat': 50.1,
          'lon': 14.5,
          'at': now.subtract(const Duration(minutes: 20)).toIso8601String(),
        },
        {
          'lat': 50.1,
          'lon': 14.5,
          'at': now.add(const Duration(minutes: 5)).toIso8601String(),
        },
        {'lat': 95.0, 'lon': 14.5, 'at': now.toIso8601String()},
        {'lat': 50.1, 'lon': 14.5},
      ]) {
        room().remoteData('ghost', RoomTopic.position, message);
      }
      room().remoteData('operator', RoomTopic.position, {
        'lat': 50.1,
        'lon': 14.5,
        'at': now.toIso8601String(),
      });
      await pumpEventQueue();

      expect(controller.peers.length, before);
    });
  });

  group('text', () {
    test('without a radio, group messages go over the room', () async {
      ble.connected = false;

      await controller.sendMeshText(
        MeshMessageDraft(
          text: 'Bez radia',
          groupId: controller.selectedGroup.id,
        ),
      );

      final texts = sent(RoomTopic.text);
      expect(texts.single['text'], 'Bez radia');
      expect(texts.single['groupId'], 'alpha');
      final message = controller.messages.first;
      expect(message.delivery, MessageDelivery.sent);
      expect(message.viaInternet, isTrue);
    });

    test('direct and other-group messages still need the radio', () async {
      ble.connected = false;

      await controller.sendCheckIn(controller.peers.first);
      await controller.sendMeshText(
        const MeshMessageDraft(text: 'Jina skupina', groupId: 'bravo'),
      );

      expect(sent(RoomTopic.text), isEmpty);
      expect(
        controller.messages
            .take(2)
            .every((m) => m.delivery == MessageDelivery.notSent),
        isTrue,
      );
    });

    test('with a radio, messages go over LoRa only', () async {
      await controller.sendMeshText(
        MeshMessageDraft(
          text: 'Pres LoRa',
          groupId: controller.selectedGroup.id,
        ),
      );
      expect(ble.written, hasLength(1));
      expect(sent(RoomTopic.text), isEmpty);
      expect(controller.messages.first.viaInternet, isFalse);
    });

    test('receives, deduplicates and plots internet messages', () async {
      final message = {
        'id': 77,
        'callSign': 'DOC',
        'groupId': 'alpha',
        'text': 'WP NET-1 | RALLY | MGRS x | LAT 50.1 | LON 14.5 | sraz',
        'at': DateTime.now().toUtc().toIso8601String(),
      };
      room().remoteData('medic', RoomTopic.text, message);
      room().remoteData('medic', RoomTopic.text, message);
      room().remoteData('medic', RoomTopic.text, {
        ...message,
        'id': 78,
        'groupId': 'bravo',
      });
      await pumpEventQueue();

      final received = controller.messages.where((m) => m.sender == 'DOC');
      expect(received, hasLength(1));
      expect(received.single.viaInternet, isTrue);
      expect(received.single.groupId, 'alpha');
      expect(controller.waypoints.any((w) => w.code == 'NET-1'), isTrue);
    });
  });

  test('viaInternet survives persistence; legacy flag is read', () {
    final message = MeshMessage(
      sender: 'DOC',
      body: 'x',
      sentAt: DateTime.utc(2026, 10, 24),
      groupId: 'alpha',
      viaInternet: true,
    );
    expect(MeshMessage.fromJson(message.toJson()).viaInternet, isTrue);
    expect(
      MeshMessage.fromJson({
        'sender': 'PTT SERVER',
        'body': 'x',
        'groupId': 'alpha',
        'internetVoice': true,
      }).viaInternet,
      isTrue,
    );
    final node = MeshNode(
      nodeNum: 1,
      callSign: 'DOC',
      latitude: 50,
      longitude: 14,
      altitudeM: 0,
      lastSeenAt: DateTime.utc(2026, 10, 24),
      viaInternet: true,
    );
    expect(MeshNode.fromJson(node.toJson()).viaInternet, isTrue);
  });
}
