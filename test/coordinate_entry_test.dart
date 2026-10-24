import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:tactical_car_app/app.dart';
import 'package:tactical_car_app/controllers/tactical_controller.dart';
import 'package:tactical_car_app/models/geo.dart';
import 'package:tactical_car_app/models/navigation.dart';
import 'package:tactical_car_app/services/mesh_packet_repository.dart';

import 'support/fakes.dart';

void main() {
  // Prague, zone 33U square VR.
  const near = LatLng(50.0, 14.4);
  final expected = parseMgrs('33U VR 58335 40478')!;

  group('parseCoordinates', () {
    test('full MGRS with or without spaces', () {
      expect(parseCoordinates('33U VR 58335 40478'), expected);
      expect(parseCoordinates('33uvr5833540478'), expected);
    });

    test('short MGRS takes the zone and square from our position', () {
      expect(parseCoordinates('VR 58335 40478', near: near), expected);
      expect(parseCoordinates('58335 40478', near: near), expected);
      expect(parseCoordinates('58335 40478'), isNull);
    });

    test('decimal degrees with dot or comma decimals', () {
      expect(
        parseCoordinates('50.0123, 14.4567'),
        const LatLng(50.0123, 14.4567),
      );
      expect(
        parseCoordinates('50.0123 14.4567'),
        const LatLng(50.0123, 14.4567),
      );
      expect(
        parseCoordinates('50,0123; 14,4567'),
        const LatLng(50.0123, 14.4567),
      );
      expect(parseCoordinates('-33.9, 151.2'), const LatLng(-33.9, 151.2));
    });

    test('typed MGRS reads back with the same digits', () {
      for (final mgrs in [
        '33U VR 58335 40478',
        '33U VR 00000 00000',
        '33U WR 99999 12345',
        '34U CA 50000 50000',
      ]) {
        final point = parseCoordinates(mgrs)!;
        expect(formatMgrs(point.latitude, point.longitude), mgrs);
      }
    });

    test('rejects garbage and out-of-range values', () {
      expect(parseCoordinates(''), isNull);
      expect(parseCoordinates('hello'), isNull);
      expect(parseCoordinates('95.0, 14.0'), isNull);
      expect(parseCoordinates('VR 583 40478', near: near), isNull);
      expect(parseCoordinates('33U VR 583 40478'), isNull);
    });
  });

  test('updating a point keeps its code and position', () async {
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
    final original = controller.addWaypoint(
      type: TacticalWaypointType.rally,
      latitude: 50.1,
      longitude: 14.4,
      code: 'HILL',
      note: 'kopec',
    );

    final updated = controller.updateWaypoint(
      original,
      type: TacticalWaypointType.danger,
      note: ' mina ',
    );

    expect(updated.code, 'HILL');
    expect(updated.latLng, original.latLng);
    expect(updated.type, TacticalWaypointType.danger);
    expect(updated.note, 'mina');
    expect(updated.priority, isTrue);
    expect(
      controller.waypoints.where((w) => w.code == 'HILL').single.note,
      'mina',
    );
  });

  group('map', () {
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

    testWidgets('typed coordinates open the point card', (tester) async {
      await login(tester);
      await tester.tap(find.byKey(const ValueKey('enter-coordinates')));
      await tester.pumpAndSettle();

      final input = find.byKey(const ValueKey('coordinate-input'));
      await tester.enterText(input, 'nesmysl');
      await tester.pump();
      expect(find.text('Neplatné souřadnice'), findsOneWidget);

      await tester.enterText(input, '33U VR 58335 40478');
      await tester.pump();
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('coordinate-preview')))
            .data,
        startsWith('33U VR 58335 40478'),
      );
      await tester.tap(find.text('Ukázat na mapě'));
      await tester.pumpAndSettle();

      final card = find.byKey(const ValueKey('point-info'));
      expect(card, findsOneWidget);
      expect(
        find.descendant(of: card, matching: find.text('33U VR 58335 40478')),
        findsOneWidget,
      );
      expect(find.text('Navigovat sem'), findsOneWidget);
    });

    testWidgets('a mission point can be edited', (tester) async {
      await login(tester);
      final sheet = find.byKey(const ValueKey('map-details-sheet'));
      await tester.drag(
        find.byKey(const ValueKey('map-sheet-handle')),
        const Offset(0, -600),
      );
      await tester.pumpAndSettle();

      final edit = find.descendant(
        of: sheet,
        matching: find.byKey(const ValueKey('edit-waypoint-OBS-2')),
      );
      await tester.scrollUntilVisible(
        edit,
        200,
        scrollable: find
            .descendant(of: sheet, matching: find.byType(Scrollable))
            .first,
      );
      // Below the fold of the 932 px test screen: press it directly.
      final button = tester.widget<IconButton>(edit);
      expect(button.onPressed, isNotNull);
      button.onPressed!();
      await tester.pumpAndSettle();

      expect(find.text('Upravit OBS-2'), findsOneWidget);
      await tester.tap(find.widgetWithText(ChoiceChip, 'DANGER'));
      await tester.enterText(
        find.widgetWithText(TextField, 'Poznámka'),
        'kulomet',
      );
      await tester.tap(find.text('Poslat změnu skupině')); // switch off
      await tester.tap(find.text('Uložit změny'));
      await tester.pumpAndSettle();

      expect(find.text('OBS-2 | DANGER'), findsWidgets);
      expect(find.text('kulomet'), findsWidgets);
    });
  });
}
