import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tactical_car_app/app.dart';
import 'package:tactical_car_app/screens/map_page.dart';
import 'package:tactical_car_app/widgets/mgrs_grid_layer.dart';

import 'support/fakes.dart';

void main() {
  test('grid spacing follows the zoom', () {
    expect(mgrsGridSpacing(5), isNull);
    expect(mgrsGridSpacing(7), 100000);
    expect(mgrsGridSpacing(11), 10000);
    expect(mgrsGridSpacing(14), 1000);
  });

  test('labels use the principal MGRS digits', () {
    expect(gridLabel(358000, 1000), '58');
    expect(gridLabel(5548000, 1000), '48');
    expect(gridLabel(302000, 1000), '02');
    expect(gridLabel(350000, 10000), '5');
  });

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

  testWidgets('grid is drawn by default and can be switched off', (
    tester,
  ) async {
    await login(tester);
    expect(find.byType(MgrsGridLayer), findsOneWidget);

    await tester.tap(find.text('Systém'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mřížka MGRS na mapě'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mapa'));
    await tester.pumpAndSettle();
    expect(find.byType(MgrsGridLayer), findsNothing);
  });

  testWidgets('tapping the map shows the point and sends it', (tester) async {
    await login(tester);

    await tester.tapAt(
      tester.getCenter(find.byType(MeshMap)) + const Offset(60, 80),
    );
    // The map waits out the double-tap window before reporting a tap.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    final card = find.byKey(const ValueKey('point-info'));
    expect(card, findsOneWidget);
    expect(
      find.descendant(of: card, matching: find.textContaining('33U VR')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.textContaining('od tebe')),
      findsOneWidget,
    );

    await tester.tap(find.text('Poslat skupině'));
    await tester.pumpAndSettle();
    expect(card, findsNothing);

    await tester.tap(find.text('Zprávy'));
    await tester.pumpAndSettle();
    expect(find.textContaining('BOD | MGRS 33U VR'), findsOneWidget);
  });
}
