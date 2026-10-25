import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tactical_car_app/app.dart';
import 'package:tactical_car_app/controllers/tactical_controller.dart';
import 'package:tactical_car_app/services/mesh_packet_repository.dart';

import 'support/fakes.dart';

void main() {
  testWidgets('the user field starts empty, then offers the last login', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 932);
    addTearDown(tester.view.reset);
    Future<void> start() async {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        TacticalCarApp(
          locationService: FakeLocationService(),
          meshtasticBleService: FakeBleService(),
        ),
      );
      await tester.pumpAndSettle();
    }

    String userField() =>
        tester.widget<TextField>(find.byType(TextField).first).controller!.text;

    await start();
    expect(userField(), isEmpty); // no built-in "operator" any more

    await tester.enterText(find.byType(TextField).first, 'Medic');
    await tester.enterText(find.byType(TextField).at(1), 'medic-2026');
    await tester.tap(find.text('Přihlásit'));
    await tester.pumpAndSettle();

    await start(); // app restarted: last user prefilled
    expect(userField(), 'medic');
  });

  test('emergency wipe forgets the last user', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final controller = TacticalController(
      locationService: FakeLocationService(),
      meshtasticBleService: FakeBleService(),
      meshPacketRepository: MeshPacketRepository(),
      nativePtt: FakeNativePttBridge(),
      carBridge: FakeCarBridge(),
    );
    addTearDown(controller.dispose);
    await controller.login('operator', 'operator-2026');
    expect(controller.lastUserName, 'operator');
    await controller.emergencyWipe();
    expect(controller.lastUserName, isNull);
  });
}
