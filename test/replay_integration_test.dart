import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tactical_car_app/app.dart';
import 'package:tactical_car_app/controllers/tactical_controller.dart';
import 'package:tactical_car_app/models/navigation.dart';
import 'package:tactical_car_app/services/mesh_packet_repository.dart';
import 'package:tactical_car_app/services/meshtastic_ble_service.dart';
import 'package:tactical_car_app/services/packet_recording.dart';
import 'package:tactical_car_app/services/replay_radio.dart';

import 'support/fakes.dart';

PacketRecording _fixture() => PacketRecording.parse(
  File('test/fixtures/tbeam_session_synthetic.txt').readAsStringSync(),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('recording format round-trips', () {
    final recording = _fixture();
    expect(recording.packets, hasLength(12));
    final again = PacketRecording.parse(recording.serialize(comment: 'x'));
    expect(
      again.packets.map((p) => p.bytes),
      recording.packets.map((p) => p.bytes),
    );
    expect(again.packets.last.offset, const Duration(milliseconds: 4000));
    expect(() => PacketRecording.parse('12 abc'), throwsFormatException);
  });

  test('repository keeps the last frames as a recording', () {
    final repository = MeshPacketRepository(recordLimit: 2);
    final start = DateTime.utc(2026, 10, 24, 10);
    for (var i = 0; i < 3; i++) {
      repository.ingest(
        MeshtasticBlePacket(
          bytes: [i],
          receivedAt: start.add(Duration(seconds: i)),
        ),
      );
    }
    final recording = repository.recording;
    expect(recording.packets.map((p) => p.bytes), [
      [1],
      [2],
    ]);
    expect(recording.packets.last.offset, const Duration(seconds: 1));
  });

  test('replaying a T-Beam session builds the operational picture', () async {
    final radio = ReplayRadio(_fixture(), speed: 0);
    final controller = TacticalController(
      locationService: FakeLocationService(),
      meshtasticBleService: radio,
      meshPacketRepository: MeshPacketRepository(),
    );
    addTearDown(controller.dispose);
    await controller.login('operator', 'operator-2026');

    await controller.connectRadio();
    await radio.done;
    await pumpEventQueue();

    expect(controller.meshConnected, isTrue);
    final self = controller.selfNode;
    expect(self.nodeNum, 0x0BADBEEF);
    expect(self.callSign, 'EAGLE');
    expect(self.batteryPercent, 77);

    final falcon = controller.peers.firstWhere((n) => n.callSign == 'FALCON');
    final viper = controller.peers.firstWhere((n) => n.callSign == 'VIPER');
    expect(falcon.batteryPercent, 23);
    expect(viper.latitude, closeTo(50.075, 1e-6));
    expect(controller.peers.where((n) => n.nodeNum == 0x0BADBEEF), isEmpty);

    final bridge = controller.messages.where(
      (m) => m.body == 'Na pozici u mostu',
    );
    expect(bridge, hasLength(1), reason: 'rebroadcast must be deduplicated');
    expect(bridge.single.sender, 'FALCON');
    final wpMessage = controller.messages.firstWhere(
      (m) => m.body.startsWith('WP OP-1'),
    );
    expect(wpMessage.groupId, 'bravo');

    final waypoints = controller.waypoints;
    final op1 = waypoints.firstWhere((w) => w.code == 'OP-1');
    expect(op1.type, TacticalWaypointType.observation);
    expect(op1.sharedBy, 'VIPER');
    expect(waypoints.any((w) => w.meshWaypointId == 9), isTrue);
    final contact = waypoints.firstWhere((w) => w.code.startsWith('CONTACT-'));
    expect(contact.note, contains('VOZIDLO'));
    expect(contact.latitude, greaterThan(falcon.latitude));
    expect(contact.longitude, greaterThan(falcon.longitude));

    // Outgoing traffic goes to the (replay) radio.
    await controller.sendCheckIn(falcon);
    expect(radio.written, hasLength(1));
  });

  testWidgets('app connects to a replayed T-Beam from the System screen', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 932);
    addTearDown(tester.view.reset);
    final radio = ReplayRadio(_fixture(), speed: 0);

    await tester.pumpWidget(
      TacticalCarApp(
        locationService: FakeLocationService(),
        meshtasticBleService: radio,
      ),
    );
    await tester.enterText(find.byType(TextField).first, 'operator');
    await tester.enterText(find.byType(TextField).at(1), 'operator-2026');
    await tester.tap(find.text('Přihlásit'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Systém'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vyhledat T-Beam'));
    // Replay timers run on the test's fake clock: pump until all frames
    // have been delivered.
    for (var i = 0; i < 30; i++) {
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(find.byTooltip('T-Beam 868 připojen'), findsOneWidget);
    expect(find.text('Kopírovat záznam paketů'), findsOneWidget);

    await tester.tap(find.text('Tým'));
    await tester.pumpAndSettle();
    // Card in the team list and own callsign in the PTT bar.
    expect(find.text('EAGLE'), findsWidgets);
    expect(find.text('FALCON'), findsOneWidget);
    // Six nodes now: the last card is below the fold, so search for it.
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.labelText == 'Vyhledat uživatele',
      ),
      'viper',
    );
    await tester.pumpAndSettle();
    expect(find.text('VIPER'), findsOneWidget);
  });
}
