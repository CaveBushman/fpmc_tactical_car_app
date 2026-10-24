import 'package:flutter_test/flutter_test.dart';
import 'package:tactical_car_app/controllers/tactical_controller.dart';
import 'package:tactical_car_app/models/messaging.dart';
import 'package:tactical_car_app/services/mesh_packet_repository.dart';
import 'package:tactical_car_app/services/meshtastic_ble_service.dart';

import 'support/fakes.dart';
import 'support/mesh_bytes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeBleService ble;
  late MeshPacketRepository repository;
  late TacticalController controller;

  setUp(() async {
    ble = FakeBleService()..connected = false;
    repository = MeshPacketRepository();
    controller = TacticalController(
      locationService: FakeLocationService(),
      meshtasticBleService: ble,
      meshPacketRepository: repository,
      nativePtt: FakeNativePttBridge(),
      carBridge: FakeCarBridge(),
    );
    await controller.login('operator', 'operator-2026');
  });

  tearDown(() => controller.dispose());

  void radioHandshakeDone() => repository.ingest(
    MeshtasticBlePacket(bytes: pbVarint(7, 1234), receivedAt: DateTime.now()),
  );

  test('pending messages go out once the radio handshake completes', () async {
    final notices = <String>[];
    controller.notices.listen(notices.add);
    for (final text in ['Prvni', 'Druha']) {
      await controller.sendMeshText(
        MeshMessageDraft(text: text, groupId: controller.selectedGroup.id),
      );
    }
    expect(ble.written, isEmpty);
    await pumpEventQueue(); // let the "not connected" notices arrive first
    notices.clear();

    ble.connected = true;
    radioHandshakeDone();
    await pumpEventQueue(times: 50);

    expect(ble.written, hasLength(2));
    final bodies = controller.messages
        .where((m) => m.body == 'Prvni' || m.body == 'Druha')
        .map((m) => m.delivery);
    expect(bodies, everyElement(MessageDelivery.sent));
    expect(notices, ['Odesláno 2 čekajících zpráv.']);
  });

  test('a failed resend stays pending without notice spam', () async {
    await controller.sendMeshText(
      MeshMessageDraft(text: 'Stale ne', groupId: controller.selectedGroup.id),
    );
    final notices = <String>[];
    controller.notices.listen(notices.add);

    radioHandshakeDone(); // still not connected
    await pumpEventQueue(times: 50);

    expect(
      controller.messages.firstWhere((m) => m.body == 'Stale ne').delivery,
      MessageDelivery.notSent,
    );
    expect(notices, isEmpty);
  });

  test('messages refused by the mesh are left for a manual retry', () async {
    ble.connected = true;
    await controller.sendMeshText(
      MeshMessageDraft(text: 'NAK', groupId: controller.selectedGroup.id),
    );
    final sentPacket = controller.messages.first.packetId!;
    repository.ingest(
      MeshtasticBlePacket(
        bytes: pbMessage(2, [
          ...pbFixed32(1, 0xA1100002),
          ...pbMessage(4, [
            ...pbVarint(1, 5),
            ...pbMessage(2, pbVarint(3, 5)),
            ...pbFixed32(6, sentPacket),
          ]),
        ]),
        receivedAt: DateTime.now(),
      ),
    );
    await pumpEventQueue();
    expect(controller.messages.first.delivery, MessageDelivery.failed);

    radioHandshakeDone();
    await pumpEventQueue(times: 50);
    expect(ble.written, hasLength(1));
    expect(controller.messages.first.delivery, MessageDelivery.failed);
  });
}
