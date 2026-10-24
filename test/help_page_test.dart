import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tactical_car_app/app.dart';
import 'package:tactical_car_app/screens/help_page.dart';
import 'package:tactical_car_app/screens/systems_page.dart';

import 'support/fakes.dart';

void main() {
  test('topics are unique and searchable without diacritics', () {
    final titles = helpTopics.map((t) => t.title).toList();
    expect(titles.toSet(), hasLength(titles.length));
    expect(
      helpTopics.where((t) => t.matches('zakladna')).map((t) => t.title),
      contains('Základna'),
    );
    expect(helpTopics.where((t) => t.matches('xyzxyz')), isEmpty);
  });

  // The team phone in both orientations, default and largest font.
  for (final size in const [Size(856, 384), Size(384, 856)]) {
    testWidgets('help opens from System and filters at $size', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
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

      await tester.tap(find.byIcon(Icons.settings_outlined).first);
      await tester.pumpAndSettle();
      final open = find.byKey(const ValueKey('open-help'));
      await tester.scrollUntilVisible(
        open,
        300,
        scrollable: find
            .descendant(
              of: find.byType(SystemsPage),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.ensureVisible(open);
      await tester.pumpAndSettle();
      await tester.tap(open);
      await tester.pumpAndSettle();
      expect(find.byType(HelpPage), findsOneWidget);

      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('help-search')),
          matching: find.byType(TextField),
        ),
        'zakladna',
      );
      await tester.pumpAndSettle();
      // Matching topics open expanded while searching.
      expect(find.textContaining('Moje základna'), findsWidgets);
      expect(find.text('Měření vzdálenosti'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
