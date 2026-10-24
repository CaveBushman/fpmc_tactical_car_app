import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tactical_car_app/app.dart';
import 'package:tactical_car_app/screens/car_mode_screen.dart';

import 'support/fakes.dart';

void main() {
  Future<FakeBleService> openCarMode(WidgetTester tester, Size size) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
    final ble = FakeBleService();
    await tester.pumpWidget(
      TacticalCarApp(
        locationService: FakeLocationService(),
        meshtasticBleService: ble,
      ),
    );
    await tester.enterText(find.byType(TextField).first, 'operator');
    await tester.enterText(find.byType(TextField).at(1), 'operator-2026');
    await tester.tap(find.text('Přihlásit'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Režim auta'));
    await tester.pumpAndSettle();
    return ble;
  }

  for (final size in const [Size(740, 360), Size(360, 740)]) {
    testWidgets('car mode fits ${size.width.toInt()}x${size.height.toInt()}', (
      tester,
    ) async {
      await openCarMode(tester, size);

      expect(tester.takeException(), isNull);
      expect(find.byType(CarModeScreen), findsOneWidget);
      expect(find.byKey(const ValueKey('car-nearest')), findsOneWidget);
      expect(find.byKey(const ValueKey('car-last-message')), findsOneWidget);
      expect(find.text('PTT – DRŽ'), findsOneWidget);
    });
  }

  testWidgets('hold-to-talk and quick report from car mode', (tester) async {
    final ble = await openCarMode(tester, const Size(740, 360));

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('car-ptt'))),
    );
    await tester.pump();
    expect(find.text('VYSÍLÁM'), findsWidgets);
    await gesture.up();
    await tester.pump();
    expect(find.text('PTT – DRŽ'), findsOneWidget);

    await tester.tap(find.text('NA POZICI'));
    await tester.pumpAndSettle();
    expect(ble.written, hasLength(1));
    expect(
      find.textContaining('NA POZICI | MGRS'),
      findsOneWidget,
      reason: 'shown as the last message',
    );

    await tester.tap(find.byTooltip('Ukončit režim auta'));
    await tester.pumpAndSettle();
    expect(find.byType(CarModeScreen), findsNothing);
  });

  testWidgets('status, quick message and target are picked in car mode', (
    tester,
  ) async {
    final ble = await openCarMode(tester, const Size(856, 384));

    // Own status.
    await tester.tap(find.byKey(const ValueKey('car-own-status')));
    await tester.pumpAndSettle();
    expect(find.text('Můj stav'), findsOneWidget);
    await tester.tap(find.text('V POHYBU'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('car-own-status')),
        matching: find.text('V POHYBU'),
      ),
      findsOneWidget,
    );
    expect(ble.written, hasLength(1));

    // Quick message from the templates.
    await tester.tap(find.text('ZPRÁVA'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('big-choice-0')),
        matching: find.text('OK'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('PŘESUN'));
    await tester.pumpAndSettle();
    expect(ble.written, hasLength(2));
    expect(find.textContaining(': PŘESUN'), findsOneWidget);

    // Navigation target from the list.
    await tester.tap(find.byKey(const ValueKey('car-pick-target')));
    await tester.pumpAndSettle();
    expect(find.text('Navigovat k'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('big-choice-1')));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Ukončit navigaci'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
