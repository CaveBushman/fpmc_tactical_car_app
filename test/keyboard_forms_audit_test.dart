import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tactical_car_app/app.dart';
import 'package:tactical_car_app/screens/map_page.dart';
import 'package:tactical_car_app/screens/systems_page.dart';

import 'support/fakes.dart';

/// Opens every form and dialog on the team phone (856 x 384 dp) with the
/// on-screen keyboard up, in both orientations and with the default and
/// the largest font. Nothing may overflow and the confirming button must
/// be reachable (scrolled into view and hit by a tap).
void main() {
  const cases = {
    // Samsung keyboard: ~190 dp in landscape, ~300 dp in portrait.
    'landscape': (size: Size(856, 384), keyboard: 190.0),
    'portrait': (size: Size(384, 856), keyboard: 300.0),
  };

  for (final MapEntry(key: orientation, value: setup) in cases.entries) {
    for (final fontScale in const [1.0, 1.35]) {
      testWidgets('$orientation, font ${(fontScale * 100).round()} %', (
        tester,
      ) async {
        SharedPreferences.setMockInitialValues({
          'settings.fontScale': fontScale,
        });
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = setup.size;
        addTearDown(tester.view.reset);

        void keyboard(bool up) => tester.view.viewInsets = up
            ? FakeViewPadding(bottom: setup.keyboard)
            : FakeViewPadding.zero;

        /// With the keyboard up: no overflow, and [button] can be scrolled
        /// into view and tapped (the tap is not performed).
        Future<void> check(String name, Finder button) async {
          keyboard(true);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: '$name: overflow');
          expect(button, findsOneWidget, reason: '$name: no button');
          await tester.ensureVisible(button);
          await tester.pumpAndSettle();
          final center = tester.getCenter(button);
          final visibleBottom = setup.size.height - setup.keyboard;
          expect(
            center.dy,
            lessThan(visibleBottom),
            reason: '$name: button hidden under the keyboard',
          );
          final hit = tester.hitTestOnBinding(center);
          final target = tester.renderObject(button);
          expect(
            hit.path.any((entry) => entry.target == target) ||
                hit.path.any(
                  (entry) =>
                      entry.target is RenderObject &&
                      _isDescendant(entry.target as RenderObject, target),
                ),
            isTrue,
            reason: '$name: button covered',
          );
          keyboard(false);
          await tester.pumpAndSettle();
        }

        Future<void> close() async {
          await tester.tapAt(const Offset(4, 4)); // barrier
          await tester.pumpAndSettle();
          if (find.byType(BottomSheet).evaluate().isNotEmpty ||
              find.byType(AlertDialog).evaluate().isNotEmpty) {
            final back = find.text('Zrušit');
            if (back.evaluate().isNotEmpty) {
              await tester.tap(back.last);
              await tester.pumpAndSettle();
            }
          }
          expect(tester.takeException(), isNull);
        }

        await tester.pumpWidget(
          TacticalCarApp(
            locationService: FakeLocationService(),
            meshtasticBleService: FakeBleService(),
          ),
        );
        await tester.pumpAndSettle();

        // Login screen.
        await check('login', find.text('Přihlásit'));
        await tester.enterText(find.byType(TextField).first, 'operator');
        await tester.enterText(find.byType(TextField).at(1), 'operator-2026');
        await tester.tap(find.text('Přihlásit'));
        await tester.pumpAndSettle();

        // Map: coordinates dialog and the new-point editor.
        await tester.tap(find.byKey(const ValueKey('enter-coordinates')));
        await tester.pumpAndSettle();
        await check('coordinates', find.text('Ukázat na mapě'));
        await close();

        await tester.longPressAt(
          tester.getCenter(find.byType(MeshMap)) + const Offset(30, 10),
        );
        await tester.pumpAndSettle();
        await check('new point', find.text('Uložit bod'));
        await close();

        // Messages: the three reports.
        await tester.tap(find.byIcon(Icons.chat_bubble_outline).first);
        await tester.pumpAndSettle();
        for (final report in const ['CONTACT', 'MEDEVAC', 'SITREP']) {
          final open = find.text(report);
          // Short layouts build the Messages tab as one lazy list.
          final scroll = find.byKey(const ValueKey('messages-scroll'));
          if (scroll.evaluate().isNotEmpty) {
            await tester.scrollUntilVisible(
              open,
              100,
              scrollable: find
                  .descendant(of: scroll, matching: find.byType(Scrollable))
                  .first,
            );
          }
          await tester.ensureVisible(open.first);
          await tester.pumpAndSettle();
          await tester.tap(open.first);
          await tester.pumpAndSettle();
          await check(report, find.text('Odeslat $report'));
          await close();
        }

        // System: quick message templates.
        await tester.tap(find.byIcon(Icons.settings_outlined).first);
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
        await tester.ensureVisible(find.text('Rychlé zprávy'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Rychlé zprávy'));
        await tester.pumpAndSettle();
        await check('quick messages', find.text('Uložit'));
        await close();
      });
    }
  }
}

bool _isDescendant(RenderObject node, RenderObject ancestor) {
  RenderObject? current = node;
  while (current != null) {
    if (identical(current, ancestor)) {
      return true;
    }
    current = current.parent;
  }
  return false;
}
