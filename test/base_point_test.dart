import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tactical_car_app/app.dart';
import 'package:tactical_car_app/controllers/tactical_controller.dart';
import 'package:tactical_car_app/services/mesh_packet_repository.dart';

import 'support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  TacticalController newController() => TacticalController(
    locationService: FakeLocationService(),
    meshtasticBleService: FakeBleService(),
    meshPacketRepository: MeshPacketRepository(),
    nativePtt: FakeNativePttBridge(),
    carBridge: FakeCarBridge(),
  );

  test('base is remembered per user and navigable', () async {
    final controller = newController();
    addTearDown(controller.dispose);
    await controller.login('operator', 'operator-2026');
    expect(controller.baseWaypoint, isNull);
    expect(controller.navigateToBase(), isFalse);

    final obs = controller.waypoints.firstWhere((w) => w.code == 'OBS-2');
    controller.setBase(obs);
    expect(controller.baseWaypoint?.code, 'OBS-2');
    expect(controller.navigateToBase(), isTrue);
    expect(controller.navTarget!.label, 'OBS-2');
    expect(
      controller.missionEvents.map((e) => e.text),
      contains('Základna: OBS-2'),
    );
    await pumpEventQueue();

    // Another user on the same device has no base; the first gets it back.
    await controller.logout();
    expect(controller.baseWaypoint, isNull);
    await controller.login('medic', 'medic-2026');
    expect(controller.baseWaypoint, isNull);
    await controller.logout();
    await controller.login('operator', 'operator-2026');
    expect(controller.baseWaypoint?.code, 'OBS-2');

    controller.setBase(null);
    expect(controller.baseWaypoint, isNull);
  });

  testWidgets('a point is marked as base and offered first in car mode', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 1200);
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

    // Edit OBS-2 from the map sheet and mark it as the base.
    await tester.drag(
      find.byKey(const ValueKey('map-sheet-handle')),
      const Offset(0, -700),
    );
    await tester.pumpAndSettle();
    final edit = find.byKey(const ValueKey('edit-waypoint-OBS-2'));
    await tester.scrollUntilVisible(
      edit,
      200,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('map-details-sheet')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    tester.widget<IconButton>(edit).onPressed!();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('base-switch')));
    await tester.tap(find.text('Poslat změnu skupině')); // keep it local
    await tester.ensureVisible(find.text('Uložit změny'));
    await tester.tap(find.text('Uložit změny'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.home), findsWidgets); // house on the map

    // Car mode: base first in the target list.
    await tester.tap(find.byTooltip('Režim auta'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('car-pick-target')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('big-choice-0')),
        matching: find.text('ZÁKLADNA OBS-2'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('big-choice-0')));
    await tester.pumpAndSettle();
    expect(find.textContaining('OBS-2  AZ'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
