import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tactical_car_app/app.dart';
import 'package:tactical_car_app/screens/map_page.dart';

import 'support/fakes.dart';

/// Walks every screen at the size of the team's phone (1080 x 2408 px at
/// density 450 = 856 x 384 dp) in both orientations, with the default and
/// the largest in-app font. Any overflow or build error fails the test.
void main() {
  const sizes = {'landscape': Size(856, 384), 'portrait': Size(384, 856)};
  const fontScales = [1.0, 1.35];

  for (final MapEntry(key: orientation, value: size) in sizes.entries) {
    for (final fontScale in fontScales) {
      testWidgets('$orientation, font ${(fontScale * 100).round()} %', (
        tester,
      ) async {
        SharedPreferences.setMockInitialValues({
          'settings.fontScale': fontScale,
        });
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          TacticalCarApp(
            locationService: FakeLocationService(),
            meshtasticBleService: FakeBleService(),
          ),
        );
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).first, 'operator');
        await tester.enterText(find.byType(TextField).at(1), 'operator-2026');
        await tester.tap(find.text('Přihlásit'));
        await tester.pumpAndSettle();

        Future<void> step(String name, Future<void> Function() action) async {
          await action();
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: name);
        }

        Future<void> tab(IconData icon) =>
            step('tab $icon', () => tester.tap(find.byIcon(icon).first));

        // Map: details sheet pulled up, a tapped point, the ruler.
        final handle = find.byKey(const ValueKey('map-sheet-handle'));
        if (handle.evaluate().isNotEmpty) {
          await step(
            'sheet up',
            () => tester.drag(handle, const Offset(0, -500)),
          );
          await step(
            'sheet down',
            () => tester.drag(handle, const Offset(0, 500)),
          );
        }
        await step('tap map', () async {
          await tester.tapAt(
            tester.getCenter(find.byType(MeshMap)) + const Offset(40, 20),
          );
          await tester.pump(const Duration(milliseconds: 500));
        });
        // The point card sits over the bottom controls; close it.
        await step('close point', () => tester.tap(find.byTooltip('Zavřít')));
        expect(
          find.byKey(const ValueKey('point-info')),
          findsNothing,
          reason: 'the point card could not be closed',
        );
        await step(
          'ruler on',
          () => tester.tap(find.byKey(const ValueKey('measure'))),
        );
        await step(
          'ruler off',
          () => tester.tap(find.byKey(const ValueKey('measure'))),
        );
        expect(
          find.byKey(const ValueKey('measure-panel')),
          findsNothing,
          reason: 'the ruler could not be switched off',
        );
        await step(
          'coordinates dialog',
          () => tester.tap(find.byKey(const ValueKey('enter-coordinates'))),
        );
        await step('close dialog', () => tester.tap(find.text('Zrušit')));

        // Other tabs, scrolled to the end.
        await tab(Icons.groups_2_outlined);
        await tab(Icons.chat_bubble_outline);
        await tab(Icons.settings_outlined);
        final scrollables = find.byType(Scrollable);
        for (var i = 0; i < 12; i++) {
          await tester.drag(scrollables.last, const Offset(0, -300));
          await tester.pump();
        }
        await step('settings scrolled', () async {});

        // Car mode.
        await tab(Icons.map_outlined);
        await step('car mode', () => tester.tap(find.byTooltip('Režim auta')));
        await step(
          'leave car mode',
          () => tester.tap(find.byTooltip('Ukončit režim auta')),
        );
      });
    }
  }
}
