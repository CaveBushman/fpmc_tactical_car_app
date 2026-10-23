import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tactical_car_app/controllers/tactical_controller.dart';
import 'package:tactical_car_app/models/messaging.dart';
import 'package:tactical_car_app/services/location_service.dart';
import 'package:tactical_car_app/services/mesh_packet_repository.dart';
import 'package:tactical_car_app/services/meshtastic_ble_service.dart';

import 'support/fakes.dart';
import 'support/mesh_bytes.dart';

void main() {
  late FakeLocationService location;
  late FakeBleService ble;
  late MeshPacketRepository repository;
  late TacticalController controller;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    location = FakeLocationService();
    ble = FakeBleService();
    repository = MeshPacketRepository();
    controller = TacticalController(
      locationService: location,
      meshtasticBleService: ble,
      meshPacketRepository: repository,
    );
  });

  tearDown(() => controller.dispose());

  void ingest(List<int> bytes) => repository.ingest(
    MeshtasticBlePacket(bytes: bytes, receivedAt: DateTime.now()),
  );

  test('login exposes session-scoped groups and starts GPS', () async {
    expect(controller.allowedGroups, isEmpty);

    final error = await controller.login('medic', 'medic-2026');

    expect(error, isNull);
    expect(controller.session?.userName, 'medic');
    expect(controller.allowedGroups.map((group) => group.id), ['alpha', 'med']);
    expect(location.startCount, 1);
  });

  test('GPS fix moves self and recomputes peer distances', () async {
    await controller.login('operator', 'operator-2026');
    final before = controller.peers.first.distanceKm;

    location.emit(
      LocationFix(
        latitude: 49.195060,
        longitude: 16.606837,
        altitudeM: 237,
        accuracyM: 5,
        timestamp: DateTime.now(),
      ),
    );
    await pumpEventQueue();

    expect(controller.selfNode.latitude, 49.195060);
    expect(controller.peers.first.distanceKm, greaterThan(before + 150));
  });

  test('notifies listeners for incoming mesh text', () async {
    await controller.login('operator', 'operator-2026');
    var notified = 0;
    controller.addListener(() => notified++);

    ingest(fromRadioText(from: 0xA1100002, text: 'Ahoj', packetId: 3));
    await pumpEventQueue();

    expect(notified, greaterThan(0));
    expect(controller.messages.first.body, 'Ahoj');
  });

  test('send failure emits a notice and keeps the message retryable', () async {
    await controller.login('operator', 'operator-2026');
    ble.connected = false;
    final notices = <String>[];
    controller.notices.listen(notices.add);

    await controller.sendMeshText(
      MeshMessageDraft(text: 'Test', groupId: controller.selectedGroup.id),
    );
    await pumpEventQueue();

    expect(notices.single, contains('T-Beam není připojen'));
    expect(controller.messages.first.delivery, MessageDelivery.notSent);
  });

  test('aging tick re-notifies during a session', () async {
    // The controller owns (and disposes) the services it is given.
    controller.dispose();
    controller = TacticalController(
      locationService: FakeLocationService(),
      meshtasticBleService: FakeBleService(),
      meshPacketRepository: MeshPacketRepository(),
      agingTick: const Duration(milliseconds: 10),
    );
    await controller.login('operator', 'operator-2026');
    var notified = 0;
    controller.addListener(() => notified++);

    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(notified, greaterThanOrEqualTo(2));
  });

  test('logout clears the session and resets messages', () async {
    await controller.login('operator', 'operator-2026');
    ingest(fromRadioText(from: 0xA1100002, text: 'Tajne', packetId: 4));
    await pumpEventQueue();

    await controller.logout();

    expect(controller.session, isNull);
    expect(controller.messages.any((m) => m.body == 'Tajne'), isFalse);
  });
}
