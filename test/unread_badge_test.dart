import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tactical_car_app/app.dart';
import 'package:tactical_car_app/services/mesh_packet_repository.dart';
import 'package:tactical_car_app/services/meshtastic_ble_service.dart';

import 'support/fakes.dart';
import 'support/mesh_bytes.dart';

void main() {
  testWidgets('Messages tab shows the unread count until opened', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 932);
    addTearDown(tester.view.reset);
    final repository = MeshPacketRepository();

    await tester.pumpWidget(
      TacticalCarApp(
        locationService: FakeLocationService(),
        meshtasticBleService: FakeBleService(),
        meshPacketRepository: repository,
      ),
    );
    await tester.enterText(find.byType(TextField).first, 'operator');
    await tester.enterText(find.byType(TextField).at(1), 'operator-2026');
    await tester.tap(find.text('Přihlásit'));
    await tester.pumpAndSettle();

    Finder badge() => find.descendant(
      of: find.byType(NavigationBar),
      matching: find.byWidgetPredicate(
        (widget) => widget is Badge && widget.isLabelVisible,
      ),
    );
    expect(badge(), findsNothing);

    for (final id in [21, 22]) {
      repository.ingest(
        MeshtasticBlePacket(
          bytes: fromRadioText(from: 0xA1100002, text: 'Hlášení', packetId: id),
          receivedAt: DateTime.now(),
        ),
      );
    }
    await tester.pumpAndSettle();
    expect(badge(), findsOneWidget);
    expect(
      find.descendant(of: badge(), matching: find.text('2')),
      findsOneWidget,
    );

    await tester.tap(find.text('Zprávy'));
    await tester.pumpAndSettle();
    expect(badge(), findsNothing);
  });
}
