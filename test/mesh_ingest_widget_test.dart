import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tactical_car_app/main.dart';
import 'package:tactical_car_app/services/mesh_packet_repository.dart';
import 'package:tactical_car_app/services/meshtastic_ble_service.dart';

import 'support/mesh_bytes.dart';

void main() {
  Future<MeshPacketRepository> login(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 932);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final repository = MeshPacketRepository();
    await tester.pumpWidget(TacticalCarApp(meshPacketRepository: repository));
    await tester.enterText(find.byType(TextField).first, 'operator');
    await tester.tap(find.text('Přihlásit'));
    await tester.pumpAndSettle();
    return repository;
  }

  void ingest(MeshPacketRepository repository, List<int> bytes) {
    repository.ingest(
      MeshtasticBlePacket(bytes: bytes, receivedAt: DateTime.now()),
    );
  }

  testWidgets('adopts node number and callsign from the connected radio', (
    tester,
  ) async {
    final repository = await login(tester);

    ingest(repository, fromRadioMyInfo(0x0BADBEEF));
    ingest(
      repository,
      fromRadioNodeInfo(
        nodeNum: 0x0BADBEEF,
        shortName: 'EAGLE',
        latitude: 49.1,
        longitude: 16.5,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Tým'));
    await tester.pumpAndSettle();

    expect(find.text('EAGLE'), findsWidgets);
    expect(find.text('RAVEN-1'), findsNothing);
    // Own NodeInfo must not appear as a separate peer.
    expect(find.text('!0BADBEEF'), findsNothing);
  });
}
