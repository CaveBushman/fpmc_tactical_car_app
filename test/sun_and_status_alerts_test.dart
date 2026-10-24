import 'package:flutter_test/flutter_test.dart';
import 'package:tactical_car_app/controllers/tactical_controller.dart';
import 'package:tactical_car_app/models/sun.dart';
import 'package:tactical_car_app/services/location_service.dart';
import 'package:tactical_car_app/services/mesh_packet_repository.dart';
import 'package:tactical_car_app/services/meshtastic_ble_service.dart';

import 'support/fakes.dart';
import 'support/mesh_bytes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Prague.
  const lat = 50.087;
  const lon = 14.421;

  group('sun', () {
    test('summer solstice: high at noon, below the horizon at midnight', () {
      // Local noon ~13:10 CEST = 11:10 UTC; altitude ~63.4°.
      expect(
        sunAltitudeDeg(DateTime.utc(2026, 6, 21, 11, 10), lat, lon),
        closeTo(63.4, 0.7),
      );
      expect(
        sunAltitudeDeg(DateTime.utc(2026, 6, 21, 23), lat, lon),
        lessThan(-10),
      );
    });

    test('civil twilight decides darkness', () {
      // June: sunset ~21:15 CEST, civil dusk ~22:00 CEST.
      expect(isDark(DateTime.utc(2026, 6, 21, 19), lat, lon), isFalse);
      expect(isDark(DateTime.utc(2026, 6, 21, 20, 30), lat, lon), isTrue);
      // December: civil dusk ~16:40 CET.
      expect(isDark(DateTime.utc(2026, 12, 21, 14), lat, lon), isFalse);
      expect(isDark(DateTime.utc(2026, 12, 21, 16), lat, lon), isTrue);
      expect(isDark(DateTime.utc(2026, 12, 21, 11), lat, lon), isFalse);
    });
  });

  test('automatic night mode follows dusk; manual switch ends it', () async {
    var now = DateTime.utc(2026, 12, 21, 11);
    final location = FakeLocationService();
    final controller = TacticalController(
      locationService: location,
      meshtasticBleService: FakeBleService(),
      meshPacketRepository: MeshPacketRepository(),
      nativePtt: FakeNativePttBridge(),
      carBridge: FakeCarBridge(),
      clock: () => now,
    );
    addTearDown(controller.dispose);
    await controller.login('operator', 'operator-2026');
    location.emit(
      LocationFix(
        latitude: lat,
        longitude: lon,
        altitudeM: 200,
        accuracyM: 5,
        timestamp: DateTime.now(),
      ),
    );
    await pumpEventQueue();

    controller.setNightModeAuto(true);
    expect(controller.nightMode, isFalse);
    now = DateTime.utc(2026, 12, 21, 17);
    expect(controller.nightMode, isTrue);

    controller.setNightMode(false);
    expect(controller.nightModeAuto, isFalse);
    expect(controller.nightMode, isFalse);
  });

  test('urgent statuses alert until answered and lead to the member', () async {
    final repository = MeshPacketRepository();
    final controller = TacticalController(
      locationService: FakeLocationService(),
      meshtasticBleService: FakeBleService(),
      meshPacketRepository: repository,
      nativePtt: FakeNativePttBridge(),
      carBridge: FakeCarBridge(),
    );
    addTearDown(controller.dispose);
    await controller.login('operator', 'operator-2026');
    var packetId = 40;
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

    await receive('STAV | SCOUT-3 | NA POZICI');
    expect(controller.urgentStatuses, isEmpty);

    await receive('STAV | SCOUT-3 | ZRANĚN');
    expect(controller.urgentStatuses.single.callSign, 'SCOUT-3');

    expect(controller.navigateToMember('SCOUT-3'), isTrue);
    expect(controller.navTarget!.label, 'SCOUT-3');

    controller.acknowledgeStatus('SCOUT-3');
    expect(controller.urgentStatuses, isEmpty);

    // A new report alerts again.
    await receive('STAV | SCOUT-3 | POTŘEBUJI PODPORU');
    expect(controller.urgentStatuses, hasLength(1));

    await receive('STAV | SCOUT-3 | OK');
    expect(controller.urgentStatuses, isEmpty);
  });
}
