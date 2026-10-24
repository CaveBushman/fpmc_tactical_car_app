import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tactical_car_app/app.dart';
import 'package:tactical_car_app/controllers/tactical_controller.dart';
import 'package:tactical_car_app/screens/systems_page.dart';
import 'package:tactical_car_app/services/location_service.dart';
import 'package:tactical_car_app/services/mesh_packet_repository.dart';
import 'package:tactical_car_app/services/settings_store.dart';

import 'support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  LocationFix fix(double lat, {double? heading, double? speed}) => LocationFix(
    latitude: lat,
    longitude: 14.4,
    altitudeM: 200,
    accuracyM: 5,
    timestamp: DateTime.now(),
    headingDeg: heading,
    speedMps: speed,
  );

  TacticalController newController(FakeLocationService location) =>
      TacticalController(
        locationService: location,
        meshtasticBleService: FakeBleService(),
        meshPacketRepository: MeshPacketRepository(),
        nativePtt: FakeNativePttBridge(),
        carBridge: FakeCarBridge(),
      );

  test('course comes from GPS while moving and is kept when stopped', () async {
    final location = FakeLocationService();
    final controller = newController(location);
    addTearDown(controller.dispose);
    await controller.login('operator', 'operator-2026');
    expect(controller.courseDeg, isNull);

    location.emit(fix(50.0, heading: 120, speed: 0.4)); // walking noise
    await pumpEventQueue();
    expect(controller.courseDeg, isNull);

    location.emit(fix(50.001, heading: 85, speed: 12));
    await pumpEventQueue();
    expect(controller.courseDeg, 85);

    location.emit(fix(50.001, heading: 300, speed: 0)); // stopped
    await pumpEventQueue();
    expect(controller.courseDeg, 85);

    await controller.logout();
    expect(controller.courseDeg, isNull);
  });

  test('heading-up and quick messages persist; blanks fall back', () async {
    final first = newController(FakeLocationService());
    addTearDown(first.dispose);
    await pumpEventQueue();
    expect(first.quickMessages, SettingsStore.defaultQuickMessages);

    first.setMapHeadingUp(true);
    first.setQuickMessages([' ok ', '', 'KONTAKT VLEVO']);
    expect(first.quickMessages, ['ok', 'KONTAKT VLEVO']);
    await pumpEventQueue();

    final second = newController(FakeLocationService());
    addTearDown(second.dispose);
    await pumpEventQueue();
    expect(second.mapHeadingUp, isTrue);
    expect(second.quickMessages, ['ok', 'KONTAKT VLEVO']);

    second.setQuickMessages(['  ', '']);
    expect(second.quickMessages, SettingsStore.defaultQuickMessages);
  });

  group('screens', () {
    Future<void> login(WidgetTester tester) async {
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
    }

    testWidgets('compass button switches heading up', (tester) async {
      await login(tester);
      final compass = find.byKey(const ValueKey('heading-up'));
      expect(compass, findsOneWidget);
      expect(
        find.byTooltip('Sever nahoře (klepni pro směr jízdy)'),
        findsOneWidget,
      );
      await tester.tap(compass);
      await tester.pumpAndSettle();
      expect(
        find.byTooltip('Směr jízdy nahoře (klepni pro sever)'),
        findsOneWidget,
      );
    });

    testWidgets('templates are edited in System and sent from Messages', (
      tester,
    ) async {
      await login(tester);
      await tester.tap(find.text('Systém'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Rychlé zprávy'),
        200,
        scrollable: find
            .descendant(
              of: find.byType(SystemsPage),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.text('Rychlé zprávy'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('quick-messages-input')),
        'KONTAKT VLEVO\nCIL ZNICEN',
      );
      await tester.tap(find.text('Uložit'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Zprávy'));
      await tester.pumpAndSettle();
      final chips = find.byKey(const ValueKey('quick-messages'));
      expect(
        find.descendant(of: chips, matching: find.text('PŘESUN')),
        findsNothing,
      );
      await tester.tap(
        find.descendant(of: chips, matching: find.text('CIL ZNICEN')),
      );
      await tester.pumpAndSettle();
      // Sent: shows up in the message list as well.
      expect(find.text('CIL ZNICEN'), findsNWidgets(2));
    });
  });
}
