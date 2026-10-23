import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
    await tester.enterText(find.byType(TextField).at(1), 'operator-2026');
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

  testWidgets('drops duplicate deliveries of the same packet', (tester) async {
    final repository = await login(tester);

    for (var i = 0; i < 3; i++) {
      ingest(
        repository,
        fromRadioText(from: 0xA1100002, text: 'Kontakt sever', packetId: 77),
      );
    }
    await tester.pumpAndSettle();

    await tester.tap(find.text('Zprávy'));
    await tester.pumpAndSettle();

    expect(find.text('Kontakt sever'), findsOneWidget);
  });

  testWidgets('routes incoming text by channel, unknown to primary', (
    tester,
  ) async {
    final repository = await login(tester);

    await tester.tap(find.text('Zprávy'));
    await tester.pumpAndSettle();
    // Select BRAVO so a fallback based on the selected index would be wrong.
    await tester.tap(find.text('BRAVO'));
    await tester.pumpAndSettle();

    ingest(
      repository,
      fromRadioText(from: 0xA1100002, text: 'Na kanalu 1', channel: 1),
    );
    ingest(
      repository,
      fromRadioText(from: 0xA1100002, text: 'Neznamy kanal', channel: 6),
    );
    await tester.pumpAndSettle();

    expect(find.text('Na kanalu 1'), findsOneWidget);
    expect(find.text('Neznamy kanal'), findsNothing);

    await tester.tap(find.text('ALPHA').first);
    await tester.pumpAndSettle();

    expect(find.text('Neznamy kanal'), findsOneWidget);
  });

  testWidgets('map renders when no other nodes are known', (tester) async {
    SharedPreferences.setMockInitialValues({
      'tactical_state_v1': jsonEncode({
        'version': 1,
        'savedAt': DateTime.now().toUtc().toIso8601String(),
        'nodes': [
          {
            'nodeNum': 0xA1100001,
            'callSign': 'RAVEN-1',
            'latitude': 50.087451,
            'longitude': 14.420671,
            'mgrs': '33U VR 58470 48210',
            'lastSeenAt': DateTime.now().toUtc().toIso8601String(),
            'isSelf': true,
          },
        ],
        'messages': [],
      }),
    });
    addTearDown(() => SharedPreferences.setMockInitialValues({}));

    await login(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('RAVEN-2'), findsNothing);
    expect(find.text('Nejbližší'), findsOneWidget);
  });
}
