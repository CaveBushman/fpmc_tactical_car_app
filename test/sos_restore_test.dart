import 'package:flutter_test/flutter_test.dart';
import 'package:tactical_car_app/controllers/tactical_controller.dart';
import 'package:tactical_car_app/models/sos.dart';
import 'package:tactical_car_app/services/mesh_packet_repository.dart';
import 'package:tactical_car_app/services/meshtastic_ble_service.dart';

import 'support/fakes.dart';
import 'support/mesh_bytes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  TacticalController newController(
    MeshPacketRepository repository, {
    Duration offset = Duration.zero,
  }) => TacticalController(
    locationService: FakeLocationService(),
    meshtasticBleService: FakeBleService(),
    meshPacketRepository: repository,
    nativePtt: FakeNativePttBridge(),
    carBridge: FakeCarBridge(),
    sosRepeat: const Duration(hours: 1),
    clock: () => DateTime.now().add(offset),
  );

  Future<void> receive(
    MeshPacketRepository repository,
    String text,
    int id,
  ) async {
    repository.ingest(
      MeshtasticBlePacket(
        bytes: fromRadioText(from: 0xA1100002, text: text, packetId: id),
        receivedAt: DateTime.now(),
      ),
    );
    await pumpEventQueue();
  }

  String call(String callSign) => SosSignal.call(
    callSign: callSign,
    mgrs: '33U VR 00000 00000',
    latitude: 50,
    longitude: 14,
  );

  test('own SOS resumes after a restart and calls again', () async {
    final first = newController(MeshPacketRepository());
    addTearDown(first.dispose);
    await first.login('operator', 'operator-2026');
    await first.startSos();
    await first.endSession('phone restarted');

    final second = newController(MeshPacketRepository());
    addTearDown(second.dispose);
    final notices = <String>[];
    second.notices.listen(notices.add);
    await second.login('operator', 'operator-2026');
    await pumpEventQueue(times: 50);

    expect(second.sosActive, isTrue);
    expect(notices, contains(startsWith('SOS obnoveno po restartu')));
    // A fresh call went out right away.
    expect(second.messages.first.body, startsWith('SOS |'));
    expect(second.missionEvents.first.text, 'SOS obnoveno po restartu');
  });

  test('a cancelled SOS stays cancelled', () async {
    final first = newController(MeshPacketRepository());
    addTearDown(first.dispose);
    await first.login('operator', 'operator-2026');
    await first.startSos();
    await first.stopSos();
    await first.endSession('restart');

    final second = newController(MeshPacketRepository());
    addTearDown(second.dispose);
    await second.login('operator', 'operator-2026');
    await pumpEventQueue(times: 50);
    expect(second.sosActive, isFalse);
  });

  test('teammates\' calls come back with "Beru"; old ones do not', () async {
    final repository = MeshPacketRepository();
    final first = newController(repository);
    addTearDown(first.dispose);
    await first.login('operator', 'operator-2026');
    await receive(repository, call('SCOUT-3'), 300);
    await receive(repository, call('MED-4'), 301);
    await first.acknowledgeSos(
      first.activeSosAlerts.firstWhere((a) => a.callSign == 'MED-4'),
    );
    await first.endSession('restart');

    final second = newController(MeshPacketRepository());
    addTearDown(second.dispose);
    await second.login('operator', 'operator-2026');
    await pumpEventQueue(times: 50);
    // SCOUT-3 shown again; MED-4 was answered and stays hidden.
    expect(second.activeSosAlerts.map((a) => a.callSign), ['SCOUT-3']);

    // An hour later the calls are too old to bring back.
    await second.endSession('restart');
    final third = newController(
      MeshPacketRepository(),
      offset: const Duration(hours: 1),
    );
    addTearDown(third.dispose);
    await third.login('operator', 'operator-2026');
    await pumpEventQueue(times: 50);
    expect(third.activeSosAlerts, isEmpty);
  });

  test('alerts round-trip through JSON', () {
    final alert = SosAlert(
      callSign: 'A',
      lastAt: DateTime(2026, 10, 24, 15),
      mgrs: '33U VR 00000 00000',
      latitude: 50.1,
      longitude: 14.2,
      acknowledged: true,
    );
    final back = SosAlert.fromJson(alert.toJson())!;
    expect(
      (back.callSign, back.lastAt, back.mgrs, back.latitude, back.acknowledged),
      ('A', alert.lastAt, alert.mgrs, 50.1, true),
    );
    expect(SosAlert.fromJson(const {}), isNull);
  });
}
