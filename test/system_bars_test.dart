import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tactical_car_app/app.dart';
import 'package:tactical_car_app/screens/systems_page.dart';

import 'support/fakes.dart';

void main() {
  testWidgets('system bars are hidden by default and can be shown again', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 932);
    addTearDown(tester.view.reset);
    final modes = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'SystemChrome.setEnabledSystemUIMode') {
          modes.add(call.arguments as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(
      TacticalCarApp(
        locationService: FakeLocationService(),
        meshtasticBleService: FakeBleService(),
      ),
    );
    await tester.pumpAndSettle();
    expect(modes.last, 'SystemUiMode.immersiveSticky');

    await tester.enterText(find.byType(TextField).first, 'operator');
    await tester.enterText(find.byType(TextField).at(1), 'operator-2026');
    await tester.tap(find.text('Přihlásit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Systém'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Skrýt systémové lišty'),
      200,
      scrollable: find
          .descendant(
            of: find.byType(SystemsPage),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skrýt systémové lišty'));
    await tester.pumpAndSettle();
    expect(modes.last, 'SystemUiMode.edgeToEdge');

    // Returning from another app re-applies the mode.
    modes.clear();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(modes, ['SystemUiMode.edgeToEdge']);
  });
}
