import 'package:flutter_test/flutter_test.dart';
import 'package:tactical_car_app/controllers/tactical_controller.dart';
import 'package:tactical_car_app/models/mission_event.dart';
import 'package:tactical_car_app/models/navigation.dart';
import 'package:tactical_car_app/models/sos.dart';
import 'package:tactical_car_app/services/mesh_packet_repository.dart';
import 'package:tactical_car_app/services/meshtastic_ble_service.dart';
import 'package:tactical_car_app/services/mission_export.dart';

import 'support/fakes.dart';
import 'support/mesh_bytes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  TacticalController newController(MeshPacketRepository repository) =>
      TacticalController(
        locationService: FakeLocationService(),
        meshtasticBleService: FakeBleService(),
        meshPacketRepository: repository,
        nativePtt: FakeNativePttBridge(),
        carBridge: FakeCarBridge(),
        sosRepeat: const Duration(milliseconds: 20),
      );

  test('notable events are logged once and survive a restart', () async {
    final repository = MeshPacketRepository();
    final controller = newController(repository);
    addTearDown(controller.dispose);
    await controller.login('operator', 'operator-2026');
    var packetId = 60;
    Future<void> receive(String text) async {
      repository.ingest(
        MeshtasticBlePacket(
          bytes: fromRadioText(
            from: 0xA1100002,
            text: text,
            packetId: packetId++,
          ),
          receivedAt: DateTime.now(),
        ),
      );
      await pumpEventQueue();
    }

    final point = controller.addWaypoint(
      type: TacticalWaypointType.rally,
      latitude: 50.1,
      longitude: 14.4,
      code: 'RV',
    );
    controller.removeWaypoint(point);
    await receive('STAV | SCOUT-3 | ZRANĚN');
    final call = SosSignal.call(
      callSign: 'SCOUT-3',
      mgrs: '33U VR 00000 00000',
      latitude: 50,
      longitude: 14,
    );
    await receive(call);
    await receive(call); // repeated every minute: logged once
    await controller.startSos();
    await controller.stopSos();

    final texts = controller.missionEvents.map((e) => e.text).toList();
    expect(texts, [
      'SOS zrušeno',
      startsWith('SOS vyhlášeno'),
      'SOS od SCOUT-3 (33U VR 00000 00000)',
      'SCOUT-3: ZRANĚN',
      'Smazán bod RV',
      startsWith('Nový bod RV (RALLY)'),
    ]);
    expect(controller.missionEvents.first.kind, MissionEventKind.sos);

    // Saved with the rest of the state; back after logging in again.
    await controller.endSession('test');
    final restarted = newController(MeshPacketRepository());
    addTearDown(restarted.dispose);
    await restarted.login('operator', 'operator-2026');
    await pumpEventQueue(times: 50);
    expect(
      restarted.missionEvents.map((e) => e.text),
      containsAllInOrder(['SOS zrušeno', 'Smazán bod RV']),
    );
  });

  test('events CSV is oldest first and escapes formulas', () {
    final csv = buildEventsCsv([
      MissionEvent(
        at: DateTime.utc(2026, 10, 24, 9),
        kind: MissionEventKind.sos,
        text: '=HYPERLINK("x")',
      ),
      MissionEvent(
        at: DateTime.utc(2026, 10, 24, 8),
        kind: MissionEventKind.waypoint,
        text: 'Nový bod; RV',
      ),
    ]);
    final lines = csv.split('\r\n');
    expect(lines.first, 'cas_utc;druh;udalost');
    expect(lines[1], '2026-10-24T08:00:00.000Z;BOD;"Nový bod; RV"');
    expect(lines[2], startsWith("2026-10-24T09:00:00.000Z;SOS;\"'=HYPERLINK"));
  });
}
