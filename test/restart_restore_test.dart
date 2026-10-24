import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:tactical_car_app/controllers/tactical_controller.dart';
import 'package:tactical_car_app/models/member_status.dart';
import 'package:tactical_car_app/models/navigation.dart';
import 'package:tactical_car_app/models/rendezvous.dart';
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
    clock: () => DateTime.now().add(offset),
  );

  test('target, rendezvous and statuses survive a restart', () async {
    final repository = MeshPacketRepository();
    final first = newController(repository);
    addTearDown(first.dispose);
    await first.login('operator', 'operator-2026');
    final obs = first.waypoints.firstWhere((w) => w.code == 'OBS-2');
    first.navigateTo(const NavTarget.waypoint('OBS-2'));
    await first.setRendezvous(
      obs,
      DateTime.now().add(const Duration(hours: 1)),
    );
    await first.setOwnStatus(MemberStatus.holding);
    repository.ingest(
      MeshtasticBlePacket(
        bytes: fromRadioText(
          from: 0xA1100002,
          text: 'STAV | SCOUT-3 | ZRANĚN',
          packetId: 200,
        ),
        receivedAt: DateTime.now(),
      ),
    );
    await pumpEventQueue();
    await first.endSession('restart');

    final second = newController(MeshPacketRepository());
    addTearDown(second.dispose);
    await second.login('operator', 'operator-2026');
    await pumpEventQueue(times: 50);
    expect(second.navTarget?.label, 'OBS-2');
    expect(second.rendezvous?.code, 'OBS-2');
    expect(second.ownStatus, MemberStatus.holding);
    expect(second.statusOf('SCOUT-3')?.status, MemberStatus.wounded);
  });

  test('a past rendezvous and a vanished target are dropped', () async {
    final first = newController(MeshPacketRepository());
    addTearDown(first.dispose);
    await first.login('operator', 'operator-2026');
    final point = first.addWaypoint(
      type: TacticalWaypointType.rally,
      latitude: 50.3,
      longitude: 14.3,
      code: 'TMP',
    );
    first.navigateTo(const NavTarget.waypoint('TMP'));
    await first.setRendezvous(
      point,
      DateTime.now().add(const Duration(minutes: 10)),
    );
    first.removeWaypoint(point); // also ends the navigation
    await pumpEventQueue();
    await first.endSession('restart');

    // Restart an hour later: the meeting is over.
    final second = newController(
      MeshPacketRepository(),
      offset: const Duration(hours: 1),
    );
    addTearDown(second.dispose);
    await second.login('operator', 'operator-2026');
    await pumpEventQueue(times: 50);
    expect(second.navTarget, isNull);
    expect(second.rendezvous, isNull);
  });

  test('JSON round trips', () {
    for (final target in const [
      NavTarget.node(42),
      NavTarget.waypoint('RV'),
      NavTarget.point(LatLng(50.1, 14.2)),
    ]) {
      expect(NavTarget.fromJson(target.toJson()), target);
    }
    expect(NavTarget.fromJson(const {}), isNull);
    final meeting = Rendezvous(
      code: 'RV',
      at: DateTime(2026, 10, 24, 15),
      setBy: 'A',
    );
    final back = Rendezvous.fromJson(meeting.toJson())!;
    expect((back.code, back.at, back.setBy), ('RV', meeting.at, 'A'));
  });
}
