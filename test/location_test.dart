import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tactical_car_app/app.dart';
import 'package:tactical_car_app/services/location_service.dart';

import 'support/fakes.dart';

void main() {
  Future<FakeLocationService> login(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 932);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final location = FakeLocationService();
    await tester.pumpWidget(TacticalCarApp(locationService: location));
    await tester.enterText(find.byType(TextField).first, 'operator');
    await tester.enterText(find.byType(TextField).at(1), 'operator-2026');
    await tester.tap(find.text('Přihlásit'));
    await tester.pumpAndSettle();
    return location;
  }

  final brnoFix = LocationFix(
    latitude: 49.195060,
    longitude: 16.606837,
    altitudeM: 237.4,
    accuracyM: 4.2,
    timestamp: DateTime.utc(2026, 10, 23, 12),
  );

  testWidgets('starts GPS after login', (tester) async {
    final location = await login(tester);

    expect(location.startCount, 1);
    expect(find.text('GPS HLEDÁ'), findsOneWidget);
  });

  testWidgets('GPS fix replaces static own position', (tester) async {
    final location = await login(tester);

    location.emit(brnoFix);
    await tester.pumpAndSettle();

    expect(find.text('49.195060'), findsOneWidget);
    expect(find.text('16.606837'), findsOneWidget);
    expect(find.text('237 m'), findsOneWidget);
    expect(find.text('GPS ±4 m'), findsOneWidget);
    expect(find.text('50.087451'), findsNothing);
  });

  testWidgets('position report uses live GPS fix', (tester) async {
    final location = await login(tester);

    location.emit(brnoFix);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Zprávy'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('NA POZICI'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('LAT 49.195060 | LON 16.606837'),
      findsOneWidget,
    );
    expect(find.textContaining('33U VR 58556 48514'), findsNothing);
  });

  testWidgets('team distances are recomputed from GPS fix', (tester) async {
    final location = await login(tester);

    location.emit(brnoFix);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Tým'));
    await tester.pumpAndSettle();

    // Demo team is in Prague, ~185 km from Brno.
    expect(find.textContaining(RegExp(r'^18\d\.\d km')), findsWidgets);
  });
}
