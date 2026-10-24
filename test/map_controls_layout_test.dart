import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tactical_car_app/app.dart';

import 'support/fakes.dart';

void main() {
  // The Samsung phone (1080 x 2408 px at density 450 = 2.8125) in both
  // orientations, plus a tablet.
  for (final size in const [Size(856, 384), Size(384, 856), Size(1280, 800)]) {
    testWidgets('map buttons are not covered by the position panel at $size', (
      tester,
    ) async {
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

      final panel = tester.getRect(
        find.byKey(const ValueKey('position-panel')),
      );
      final map = tester.getRect(find.byKey(const ValueKey('mesh-map')));
      for (final key in const [
        'measure',
        'enter-coordinates',
        'recenter',
        'heading-up',
      ]) {
        final button = tester.getRect(find.byKey(ValueKey(key)));
        expect(
          button.overlaps(panel),
          isFalse,
          reason: '$key $button overlaps the position panel $panel',
        );
        expect(
          map.contains(button.topLeft) && map.contains(button.bottomRight),
          isTrue,
          reason: '$key $button is outside the map $map',
        );
      }
    });
  }
}
