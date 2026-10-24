import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tactical_car_app/app.dart';
import 'package:tactical_car_app/screens/systems_page.dart';

import 'support/fakes.dart';

void main() {
  Future<void> start(WidgetTester tester, {bool login = true}) async {
    await tester.pumpWidget(
      TacticalCarApp(
        locationService: FakeLocationService(),
        meshtasticBleService: FakeBleService(),
      ),
    );
    await tester.pumpAndSettle();
    if (login) {
      await tester.enterText(find.byType(TextField).first, 'operator');
      await tester.enterText(find.byType(TextField).at(1), 'operator-2026');
      await tester.tap(find.text('Přihlásit'));
      await tester.pumpAndSettle();
    }
  }

  final nightFilter = find.byKey(const ValueKey('night-mode'));

  testWidgets('night mode is switched in System and survives a restart', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 932);
    addTearDown(tester.view.reset);

    await start(tester);
    expect(nightFilter, findsNothing);

    await tester.tap(find.text('Systém'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Noční režim'),
      200,
      scrollable: find
          .descendant(
            of: find.byType(SystemsPage),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Noční režim'));
    await tester.pumpAndSettle();
    expect(nightFilter, findsOneWidget);

    // Fresh app with the same stored preferences: red from the start,
    // even on the login screen.
    await tester.pumpWidget(const SizedBox());
    await start(tester, login: false);
    expect(nightFilter, findsOneWidget);
  });

  testWidgets('car mode has a night mode toggle', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 740);
    addTearDown(tester.view.reset);

    await start(tester);
    await tester.tap(find.byTooltip('Režim auta'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Zapnout noční režim'));
    await tester.pumpAndSettle();
    expect(nightFilter, findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('Vypnout noční režim'));
    await tester.pumpAndSettle();
    expect(nightFilter, findsNothing);
  });
}
