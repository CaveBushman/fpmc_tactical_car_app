import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tactical_car_app/main.dart';

void main() {
  Future<void> login(
    WidgetTester tester, {
    String userName = 'operator',
  }) async {
    await tester.pumpWidget(const TacticalCarApp());
    expect(find.text('Přihlásit'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, userName);
    await tester.tap(find.text('Přihlásit'));
    await tester.pumpAndSettle();
  }

  testWidgets('renders tactical dashboard smoke test', (tester) async {
    await login(tester);

    expect(find.text('FIRST PRIVATE MILITARY COMPANY'), findsOneWidget);
    expect(find.text('RAVEN-1'), findsWidgets);
    expect(find.text('T-Beam 868'), findsOneWidget);
    expect(find.text('PTT'), findsOneWidget);
    expect(find.text('Mapa'), findsOneWidget);
  });

  testWidgets('uses bottom navigation in portrait', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 932);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await login(tester);

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
  });

  testWidgets('uses navigation rail and side panel in landscape', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(932, 430);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await login(tester);

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byType(NodeCard), findsNothing);

    await tester.tap(find.byIcon(Icons.groups_2_outlined));
    await tester.pumpAndSettle();

    expect(find.byType(NodeCard), findsWidgets);
  });

  testWidgets('shows font size slider in system settings', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 932);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await login(tester);

    await tester.tap(find.text('Systém'));
    await tester.pumpAndSettle();

    expect(find.text('Velikost písma'), findsOneWidget);
    expect(find.byType(Slider), findsOneWidget);
  });

  testWidgets('supports communication groups in messages', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 932);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await login(tester);

    await tester.tap(find.text('Zprávy'));
    await tester.pumpAndSettle();

    expect(find.text('ALPHA'), findsWidgets);
    expect(find.text('BRAVO'), findsOneWidget);
    expect(find.text('COMMAND'), findsNothing);
    expect(find.text('Na pozici. Vidim trasu k bodu BRAVO.'), findsOneWidget);

    await tester.tap(find.text('BRAVO'));
    await tester.pumpAndSettle();

    expect(
      find.text('BRAVO zustava jako zalozni presunovy kanal.'),
      findsOneWidget,
    );
    expect(find.text('Na pozici. Vidim trasu k bodu BRAVO.'), findsNothing);
    expect(find.textContaining('PTT BRAVO'), findsOneWidget);
  });

  testWidgets('quick position message includes complete MGRS', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 932);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await login(tester);

    await tester.tap(find.text('Zprávy'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('NA POZICI'));
    await tester.pumpAndSettle();

    expect(find.textContaining('NA POZICI | MGRS'), findsOneWidget);
    expect(find.textContaining('33U VR 58470 48210'), findsOneWidget);
  });

  testWidgets('shares waypoint to current Meshtastic group', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 932);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await login(tester);

    await tester.drag(find.byType(ListView).first, const Offset(0, -520));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Sdílet RALLY-1'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Zprávy'));
    await tester.pumpAndSettle();

    expect(find.textContaining('WP RALLY-1 | RALLY'), findsOneWidget);
    expect(find.textContaining('33U VR 58009 48063'), findsOneWidget);
  });

  testWidgets('commander can access command group', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 932);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await login(tester, userName: 'commander');

    await tester.tap(find.text('Zprávy'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('COMMAND'),
      500,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('COMMAND'), findsOneWidget);
    await tester.tap(find.text('COMMAND'));
    await tester.pumpAndSettle();

    expect(find.text('Kontrola spojeni a prihlaseni posadek.'), findsOneWidget);
  });
}
