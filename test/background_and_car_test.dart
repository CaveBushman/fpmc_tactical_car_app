import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tactical_car_app/controllers/ptt_controller.dart';
import 'package:tactical_car_app/controllers/tactical_controller.dart';
import 'package:tactical_car_app/models/navigation.dart';
import 'package:tactical_car_app/services/backend_client.dart';
import 'package:tactical_car_app/services/mesh_packet_repository.dart';
import 'package:tactical_car_app/services/meshtastic_ble_service.dart';
import 'package:tactical_car_app/services/native_bridges.dart';

import 'support/fakes.dart';
import 'support/mesh_bytes.dart';

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
  late FakeNativePttBridge nativePtt;
  late FakeCarBridge car;
  late FakeBleService ble;
  late MeshPacketRepository repository;
  late List<FakeVoiceTransport> transports;
  late TacticalController controller;

  TacticalController build({BackendClient? backend}) => TacticalController(
    locationService: FakeLocationService(),
    meshtasticBleService: ble,
    meshPacketRepository: repository,
    backend: backend,
    voiceTransportFactory: () {
      final transport = FakeVoiceTransport();
      transports.add(transport);
      return transport;
    },
    nativePtt: nativePtt,
    carBridge: car,
  );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    nativePtt = FakeNativePttBridge();
    car = FakeCarBridge();
    ble = FakeBleService();
    repository = MeshPacketRepository();
    transports = [];
    controller = build(backend: _backend());
  });

  tearDown(() => controller.dispose());

  test(
    'joined PTT runs the foreground service and mirrors its state',
    () async {
      await controller.login('operator', 'pw');
      await pumpEventQueue();

      expect(controller.ptt.status, PttStatus.ready);
      expect(nativePtt.calls.last, 'show ALPHA připraveno');

      transports.last.remoteFloor('medic', 'take', DateTime.now());
      await pumpEventQueue();
      expect(nativePtt.calls.last, 'show ALPHA mluví medic');

      await controller.logout();
      expect(nativePtt.calls.last, 'hide');
    },
  );

  test('demo PTT does not start the background service', () async {
    controller.dispose();
    controller = build();
    await controller.login('operator', 'operator-2026');
    await pumpEventQueue();

    expect(controller.ptt.isDemo, isTrue);
    expect(nativePtt.calls, isEmpty);
  });

  test('hardware buttons drive PTT: hold and toggle', () async {
    await controller.login('operator', 'pw');
    await pumpEventQueue();

    nativePtt.buttonController.add(NativePttButton.down);
    await pumpEventQueue();
    expect(controller.ptt.status, PttStatus.transmitting);
    nativePtt.buttonController.add(NativePttButton.up);
    await pumpEventQueue();
    expect(controller.ptt.status, PttStatus.ready);

    nativePtt.buttonController.add(NativePttButton.toggle);
    await pumpEventQueue();
    expect(controller.ptt.status, PttStatus.transmitting);
    expect(transports.last.microphoneEnabled, isTrue);
    nativePtt.buttonController.add(NativePttButton.toggle);
    await pumpEventQueue();
    expect(controller.ptt.status, PttStatus.ready);
    expect(transports.last.microphoneEnabled, isFalse);
  });

  test('volume key setting is forwarded to the native side', () async {
    controller.setVolumeKeyPtt(true);
    expect(nativePtt.volumeKeyPtt, isTrue);
    expect(controller.volumeKeyPtt, isTrue);
  });

  test('Android Auto gets nearest targets with positions', () async {
    await controller.login('operator', 'pw');
    await pumpEventQueue();
    // A real session starts empty; a medevac point is added.
    controller.addWaypoint(
      type: TacticalWaypointType.medevac,
      latitude: 50.083846,
      longitude: 14.430171,
      code: 'MED-POINT',
    );
    await pumpEventQueue();

    expect(car.targets, isNotEmpty);
    expect(car.targets.length, lessThanOrEqualTo(6));
    final medPoint = car.targets.firstWhere((t) => t.title == 'MED-POINT');
    expect(medPoint.priority, isTrue);
    expect(medPoint.latitude, closeTo(50.083846, 1e-6));
    final updates = car.targetUpdates;

    // Unchanged data is not re-sent on every notify.
    controller.setFontScale(1.1);
    expect(car.targetUpdates, updates);
  });

  test('messages are posted as car notifications only in background', () async {
    await controller.login('operator', 'pw');
    repository.ingest(
      MeshtasticBlePacket(
        bytes: fromRadioNodeInfo(nodeNum: 0xA1100002, shortName: 'RAVEN-2'),
        receivedAt: DateTime.now(),
      ),
    );

    repository.ingest(
      MeshtasticBlePacket(
        bytes: fromRadioText(from: 0xA1100002, text: 'v popredi', packetId: 1),
        receivedAt: DateTime.now(),
      ),
    );
    await pumpEventQueue();
    expect(car.notifications, isEmpty);

    controller.setAppInForeground(false);
    repository.ingest(
      MeshtasticBlePacket(
        bytes: fromRadioText(from: 0xA1100002, text: 'na pozadi', packetId: 2),
        receivedAt: DateTime.now(),
      ),
    );
    await pumpEventQueue();
    expect(car.notifications, ['alpha RAVEN-2: na pozadi']);
  });

  test('voice reply from the car is sent to the group', () async {
    await controller.login('operator', 'pw');

    car.replyController.add(const CarReply(groupId: 'bravo', text: 'Rozumim'));
    car.replyController.add(const CarReply(groupId: 'command', text: 'nope'));
    await pumpEventQueue();

    final sent = controller.messages.where((m) => m.body == 'Rozumim');
    expect(sent.single.groupId, 'bravo');
    expect(controller.messages.any((m) => m.body == 'nope'), isFalse);
    expect(ble.written, hasLength(1));
  });
}
