import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:tactical_car_app/app.dart';
import 'package:tactical_car_app/models/geo.dart';
import 'package:tactical_car_app/screens/messages_page.dart';

import 'support/fakes.dart';

void main() {
  group('coordinatesInText', () {
    test('prefers LAT/LON, falls back to full MGRS', () {
      expect(
        coordinatesInText(
          'NA POZICI | MGRS 33U VR 58335 40478 | LAT 50.012345 | LON 14.456789',
        ),
        const LatLng(50.012345, 14.456789),
      );
      final mgrs = coordinatesInText('CONTACT u 33U VR 58335 40478, 2 osoby')!;
      expect(formatMgrs(mgrs.latitude, mgrs.longitude), '33U VR 58335 40478');
      expect(coordinatesInText('SOS | ALFA | 33uvr5833540478'), isNotNull);
    });

    test('ignores text without a position', () {
      expect(coordinatesInText('OK'), isNull);
      expect(coordinatesInText('Přesun za 10 min, 3 vozidla'), isNull);
      expect(coordinatesInText('LAT 95.0 LON 14.0'), isNull);
    });
  });

  group('actions', () {
    Future<void> login(WidgetTester tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(430, 1400);
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

    testWidgets('team card opens a direct message and navigation', (
      tester,
    ) async {
      await login(tester);
      await tester.tap(find.text('Tým'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('message-member-SCOUT-3')));
      await tester.pumpAndSettle();

      expect(find.byType(MessagesPage), findsOneWidget);
      expect(find.textContaining('SCOUT-3 / !'), findsOneWidget);
      // The composer addresses SCOUT-3 directly.
      expect(
        find.widgetWithText(TextField, 'Zpráva pro SCOUT-3'),
        findsOneWidget,
      );

      await tester.tap(find.text('Tým'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('navigate-member-SCOUT-3')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('clear-nav-target')), findsOneWidget);
    });

    testWidgets('a position in a message is shown on the map', (tester) async {
      await login(tester);
      await tester.tap(find.text('Zprávy'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('NA POZICI'));
      await tester.pumpAndSettle();

      await tester.longPress(find.textContaining('NA POZICI | MGRS').first);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('message-copy')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('message-show-on-map')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('point-info')), findsOneWidget);
      expect(find.text('Navigovat sem'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
