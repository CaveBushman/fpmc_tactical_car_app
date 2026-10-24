import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tactical_car_app/controllers/tactical_controller.dart';
import 'package:tactical_car_app/models/mesh_node.dart';
import 'package:tactical_car_app/models/messaging.dart';
import 'package:tactical_car_app/models/navigation.dart';
import 'package:tactical_car_app/services/location_service.dart';
import 'package:tactical_car_app/services/mesh_packet_repository.dart';
import 'package:tactical_car_app/services/meshtastic_ble_service.dart';
import 'package:tactical_car_app/services/tactical_state_store.dart';

import 'support/fakes.dart';
import 'support/mesh_bytes.dart';

void main() {
  // Platform channels (native PTT / car bridges) need the binding.
  TestWidgetsFlutterBinding.ensureInitialized();

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

  test('telemetry updates peer and own T-Beam battery', () async {
    await controller.login('operator', 'operator-2026');
    ingest(fromRadioMyInfo(0x0BADBEEF));
    ingest(fromRadioTelemetry(from: 0xA1100002, battery: 17));
    ingest(fromRadioTelemetry(from: 0x0BADBEEF, battery: 101));
    await pumpEventQueue();

    final raven2 = controller.peers.firstWhere(
      (node) => node.callSign == 'RAVEN-2',
    );
    expect(raven2.batteryPercent, 17);
    expect(controller.selfNode.batteryPercent, 101);
  });

  test('new node without telemetry has unknown battery', () async {
    await controller.login('operator', 'operator-2026');
    ingest(
      fromRadioNodeInfo(
        nodeNum: 0x0000BEEF,
        shortName: 'NEW',
        latitude: 50.1,
        longitude: 14.4,
      ),
    );
    await pumpEventQueue();

    final node = controller.peers.firstWhere((node) => node.callSign == 'NEW');
    expect(node.batteryPercent, isNull);
  });

  test('incoming WP text adds a shared waypoint', () async {
    await controller.login('operator', 'operator-2026');
    ingest(
      fromRadioText(
        from: 0xA1100002,
        text:
            'WP CP-4 | SUPPLY | MGRS 33U VR 1 2 | LAT 50.1 | LON 14.45 | voda',
        packetId: 11,
      ),
    );
    await pumpEventQueue();

    final waypoint = controller.waypoints.firstWhere((w) => w.code == 'CP-4');
    expect(waypoint.type, TacticalWaypointType.supply);
    expect(waypoint.sharedBy, 'RAVEN-2');
  });

  test(
    'native mesh waypoint is added, updated and deleted by expiry',
    () async {
      await controller.login('operator', 'operator-2026');
      ingest(fromRadioWaypoint(from: 0xA1100002, id: 5, name: 'Sraz'));
      ingest(
        fromRadioWaypoint(
          from: 0xA1100002,
          id: 5,
          name: 'Sraz',
          latitude: 50.2,
        ),
      );
      await pumpEventQueue();

      final matches = controller.waypoints.where((w) => w.meshWaypointId == 5);
      expect(matches, hasLength(1));
      expect(matches.single.latitude, closeTo(50.2, 1e-6));

      ingest(fromRadioWaypoint(from: 0xA1100002, id: 5, expire: 1));
      await pumpEventQueue();

      expect(controller.waypoints.where((w) => w.meshWaypointId == 5), isEmpty);
    },
  );

  test('added waypoints get unique codes and can be removed', () async {
    await controller.login('operator', 'operator-2026');

    final first = controller.addWaypoint(
      type: TacticalWaypointType.danger,
      latitude: 50.1,
      longitude: 14.4,
    );
    final second = controller.addWaypoint(
      type: TacticalWaypointType.danger,
      latitude: 50.2,
      longitude: 14.5,
    );
    final named = controller.addWaypoint(
      type: TacticalWaypointType.rally,
      latitude: 50.2,
      longitude: 14.5,
      code: 'rally 1',
    );

    expect(first.code, 'DANGER-1');
    expect(second.code, 'DANGER-2');
    // RALLY-1 is taken by the demo data.
    expect(named.code, 'RALLY-1-1');
    expect(first.priority, isTrue);

    controller.removeWaypoint(first);
    expect(controller.waypoints.contains(first), isFalse);
  });

  test('waypoints survive restart for the same user', () async {
    await controller.login('operator', 'operator-2026');
    controller.addWaypoint(
      type: TacticalWaypointType.observation,
      latitude: 50.1,
      longitude: 14.4,
      code: 'HILL',
    );
    controller.removeWaypoint(
      controller.waypoints.firstWhere((w) => w.code == 'OBS-2'),
    );
    await pumpEventQueue();

    final restarted = TacticalController(
      locationService: FakeLocationService(),
      meshtasticBleService: FakeBleService(),
      meshPacketRepository: MeshPacketRepository(),
    );
    addTearDown(restarted.dispose);
    await restarted.login('operator', 'operator-2026');
    await pumpEventQueue(times: 50);

    final codes = restarted.waypoints.map((w) => w.code);
    expect(codes, contains('HILL'));
    expect(codes, isNot(contains('OBS-2')));
  });

  test('nodes not heard for a day are hidden and not saved again', () async {
    MeshNode node(int num, String callSign, Duration ago) => MeshNode(
      nodeNum: num,
      callSign: callSign,
      latitude: 50.1,
      longitude: 14.4,
      altitudeM: 200,
      lastSeenAt: DateTime.now().subtract(ago),
    );
    await const TacticalStateStore().save(
      nodes: [
        for (final n in [
          node(1, 'SELF', const Duration(days: 3)).copyWith(isSelf: true),
          node(2, 'FRESH', const Duration(hours: 2)),
          node(3, 'OLD', const Duration(hours: 25)),
        ])
          n.toJson(),
      ],
      messages: const [],
      waypoints: const [],
      track: const [],
      owner: 'operator',
    );

    await controller.login('operator', 'operator-2026');
    await pumpEventQueue(times: 50);

    expect(controller.nodes.map((n) => n.callSign), ['SELF', 'FRESH']);
    expect(controller.peers.map((n) => n.callSign), ['FRESH']);

    // Ending the session saves the state; the expired node is left out.
    await controller.endSession('test');
    final saved = await const TacticalStateStore().load();
    expect(saved!.nodes.map((json) => json['callSign']), ['SELF', 'FRESH']);
  });

  test('CONTACT reports become DANGER points for sender and receivers', () async {
    await controller.login('operator', 'operator-2026');
    final self = controller.selfNode;

    await controller.sendMeshText(
      MeshMessageDraft(
        text:
            'CONTACT | MGRS ${self.mgrs} | DIR 180 | DIST 500 m | TYPE DRON | SIZE 1 | nizko',
        groupId: controller.selectedGroup.id,
      ),
    );
    ingest(
      fromRadioText(
        from: 0xA1100002,
        text:
            'CONTACT | MGRS ${self.mgrs} | DIR 000 | DIST 200 m | TYPE OSOBA | SIZE 3 | x',
        packetId: 21,
      ),
    );
    await pumpEventQueue();

    final contacts = controller.waypoints
        .where((w) => w.code.startsWith('CONTACT-'))
        .toList();
    expect(contacts, hasLength(2));
    expect(
      contacts.every((w) => w.type == TacticalWaypointType.danger),
      isTrue,
    );
    final own = contacts.firstWhere((w) => w.sharedBy == self.callSign);
    expect(own.latitude, lessThan(self.latitude));
    expect(own.note, contains('DRON'));
    final received = contacts.firstWhere((w) => w.sharedBy == 'RAVEN-2');
    expect(received.latitude, greaterThan(self.latitude));
  });

  test('settings persist across restarts', () async {
    await controller.login('operator', 'operator-2026');
    controller.setFontScale(1.25);
    controller.selectGroup(1);
    controller.setVolumeKeyPtt(true);
    await pumpEventQueue();
    expect(controller.selectedGroup.id, 'bravo');

    final restarted = TacticalController(
      locationService: FakeLocationService(),
      meshtasticBleService: FakeBleService(),
      meshPacketRepository: MeshPacketRepository(),
    );
    addTearDown(restarted.dispose);
    await pumpEventQueue();
    expect(restarted.fontScale, 1.25);
    expect(restarted.volumeKeyPtt, isTrue);

    await restarted.login('operator', 'operator-2026');
    expect(restarted.selectedGroup.id, 'bravo');

    // Another user starts on their own default group.
    final other = TacticalController(
      locationService: FakeLocationService(),
      meshtasticBleService: FakeBleService(),
      meshPacketRepository: MeshPacketRepository(),
    );
    addTearDown(other.dispose);
    await other.login('medic', 'medic-2026');
    expect(other.selectedGroup.id, 'alpha');
  });
}
