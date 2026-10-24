import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tactical_car_app/app.dart';
import 'package:tactical_car_app/controllers/tactical_controller.dart';
import 'package:tactical_car_app/models/member_status.dart';
import 'package:tactical_car_app/models/messaging.dart';
import 'package:tactical_car_app/services/mesh_packet_repository.dart';
import 'package:tactical_car_app/services/meshtastic_ble_service.dart';

import 'support/fakes.dart';
import 'support/mesh_bytes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('status messages round-trip and other text is ignored', () {
    for (final status in MemberStatus.values) {
      final parsed = MemberStatus.parse(status.shareText('RAVEN-2'))!;
      expect(parsed.callSign, 'RAVEN-2');
      expect(parsed.status, status);
    }
    expect(
      MemberStatus.parse('STAV | RAVEN-2 | zraněn')!.status,
      MemberStatus.wounded,
    );
    expect(MemberStatus.parse('STAV | RAVEN-2 | HLADOVÝ'), isNull);
    expect(MemberStatus.parse('OK'), isNull);
  });

  test('peers\' status is kept and own status is sent', () async {
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

    repository.ingest(
      MeshtasticBlePacket(
        bytes: fromRadioText(
          from: 0xA1100002,
          text: 'STAV | SCOUT-3 | ZRANĚN',
          packetId: 31,
        ),
        receivedAt: DateTime.now(),
      ),
    );
    await pumpEventQueue();
    expect(controller.statusOf('SCOUT-3')!.status, MemberStatus.wounded);

    await controller.setOwnStatus(MemberStatus.needSupport);
    expect(controller.ownStatus, MemberStatus.needSupport);
    final sent = controller.messages.first;
    expect(
      sent.body,
      'STAV | ${controller.selfNode.callSign} | POTŘEBUJI PODPORU',
    );
    expect(sent.priority, isTrue);
    expect(sent.delivery, isNot(MessageDelivery.received));

    await controller.logout();
    expect(controller.statusOf('SCOUT-3'), isNull);
  });

  testWidgets('own status is picked on the Team tab', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 932);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      TacticalCarApp(
        locationService: FakeLocationService(),
        meshtasticBleService: FakeBleService(),
      ),
    );
    await tester.enterText(find.byType(TextField).first, 'operator');
    await tester.enterText(find.byType(TextField).at(1), 'operator-2026');
    await tester.tap(find.text('Přihlásit'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Tým'));
    await tester.pumpAndSettle();
    final picker = find.byKey(const ValueKey('own-status'));
    await tester.tap(
      find.descendant(of: picker, matching: find.text('NA POZICI')),
    );
    await tester.pumpAndSettle();

    final chip = tester.widget<ChoiceChip>(
      find.ancestor(
        of: find.descendant(of: picker, matching: find.text('NA POZICI')),
        matching: find.byType(ChoiceChip),
      ),
    );
    expect(chip.selected, isTrue);
    // Own card shows it too.
    expect(find.textContaining('NA POZICI · '), findsOneWidget);
  });
}
