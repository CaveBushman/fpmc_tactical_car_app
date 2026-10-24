import 'package:flutter_test/flutter_test.dart';
import 'package:tactical_car_app/controllers/tactical_controller.dart';
import 'package:tactical_car_app/models/navigation.dart';
import 'package:tactical_car_app/services/mesh_packet_repository.dart';
import 'package:tactical_car_app/services/meshtastic_ble_service.dart';

import 'support/fakes.dart';
import 'support/mesh_bytes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final created = DateTime(2026, 10, 24, 8);
  TacticalWaypoint point({String? sharedBy, DateTime? at}) => TacticalWaypoint(
    code: 'P',
    type: TacticalWaypointType.observation,
    latitude: 50,
    longitude: 14,
    note: '',
    sharedBy: sharedBy,
    createdAt: at,
  );

  test('age label, fading and old received points', () {
    final received = point(sharedBy: 'SCOUT-3', at: created);
    expect(received.ageLabelAt(created), 'teď');
    expect(
      received.ageLabelAt(created.add(const Duration(minutes: 35))),
      'před 35 min',
    );
    expect(
      received.ageLabelAt(created.add(const Duration(hours: 3))),
      'před 3 h',
    );
    expect(
      received.isStaleAt(created.add(const Duration(minutes: 59))),
      isFalse,
    );
    expect(received.isStaleAt(created.add(const Duration(hours: 1))), isTrue);
    expect(
      received.isOldReceivedAt(created.add(const Duration(hours: 5))),
      isFalse,
    );
    expect(
      received.isOldReceivedAt(created.add(const Duration(hours: 6))),
      isTrue,
    );

    // Own and built-in points are never offered for clean-up.
    final own = point(at: created);
    expect(own.isOldReceivedAt(created.add(const Duration(days: 1))), isFalse);
    expect(point().ageLabelAt(created), isNull);
    expect(point().isStaleAt(created), isFalse);
  });

  test('clean-up removes only old received points and logs it', () async {
    var offset = Duration.zero;
    final repository = MeshPacketRepository();
    final controller = TacticalController(
      locationService: FakeLocationService(),
      meshtasticBleService: FakeBleService(),
      meshPacketRepository: repository,
      nativePtt: FakeNativePttBridge(),
      carBridge: FakeCarBridge(),
      clock: () => DateTime.now().add(offset),
    );
    addTearDown(controller.dispose);
    await controller.login('operator', 'operator-2026');

    repository.ingest(
      MeshtasticBlePacket(
        bytes: fromRadioText(
          from: 0xA1100002,
          text:
              'WP OBS-9 | OBS | MGRS 33U VR 00000 00000 | LAT 50.100000 | LON 14.400000 | most',
          packetId: 90,
        ),
        receivedAt: DateTime.now(),
      ),
    );
    await pumpEventQueue();
    controller.addWaypoint(
      type: TacticalWaypointType.rally,
      latitude: 50.2,
      longitude: 14.4,
      code: 'MY',
    );
    expect(controller.oldReceivedWaypoints, isEmpty);
    expect(controller.clearOldReceivedWaypoints(), 0);

    offset = const Duration(hours: 7);
    expect(controller.oldReceivedWaypoints.map((w) => w.code), ['OBS-9']);
    expect(controller.clearOldReceivedWaypoints(), 1);
    final codes = controller.waypoints.map((w) => w.code);
    expect(codes, isNot(contains('OBS-9')));
    expect(codes, contains('MY'));
    expect(
      controller.missionEvents.first.text,
      'Smazány staré přijaté body (počet: 1)',
    );
  });
}
