import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tactical_car_app/app.dart';
import 'package:tactical_car_app/screens/map_page.dart';
import 'package:tactical_car_app/widgets/position_widgets.dart';
import 'package:tactical_car_app/widgets/node_widgets.dart';

Finder _textFieldWithLabel(String label) {
  return find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.labelText == label,
  );
}

Finder _textFieldWithHint(String hint) {
  return find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.hintText == hint,
  );
}

void main() {
  Future<void> login(
    WidgetTester tester, {
    String userName = 'operator',
  }) async {
    await tester.pumpWidget(const TacticalCarApp());
    expect(find.text('Přihlásit'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, userName);
    await tester.enterText(find.byType(TextField).at(1), '$userName-2026');
    await tester.tap(find.text('Přihlásit'));
    await tester.pumpAndSettle();
  }

  testWidgets('renders tactical dashboard smoke test', (tester) async {
    await login(tester);

    expect(find.text('FIRST PRIVATE MILITARY COMPANY'), findsOneWidget);
    expect(find.text('RAVEN-1'), findsWidgets);
    expect(find.byTooltip('T-Beam 868 nepřipojen'), findsOneWidget);
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
    expect(find.textContaining('33U VR 58556 48514'), findsOneWidget);
  });

  testWidgets('shares waypoint to current Meshtastic group', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 932);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await login(tester);

    await tester.scrollUntilVisible(
      find.text('Navigace'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    final medPointShareButton = find.byKey(
      const ValueKey('share-nav-MED-POINT'),
    );

    await tester.tap(medPointShareButton);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Zprávy'));
    await tester.pumpAndSettle();

    expect(find.textContaining('WP MED-POINT | MEDEVAC'), findsOneWidget);
    expect(find.textContaining('33U VR 59048 48110'), findsOneWidget);
  });

  testWidgets('shows tactical navigation cards on map', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 932);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await login(tester);

    await tester.scrollUntilVisible(
      find.text('Navigace'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('Navigace'), findsOneWidget);
    expect(find.textContaining('MED-POINT | MEDEVAC'), findsWidgets);
    expect(find.text('AZ'), findsWidgets);
    expect(find.text('DIST'), findsWidgets);
    expect(find.text('ETA'), findsWidgets);
  });

  testWidgets('highlights stale/lost nodes and sends check-in', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 932);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await login(tester);

    await tester.tap(find.text('Tým'));
    await tester.pumpAndSettle();

    expect(find.text('STALE'), findsOneWidget);
    expect(find.text('LOST'), findsOneWidget);

    await tester.tap(find.byTooltip('CHECK-IN MED-4'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Zprávy'));
    await tester.pumpAndSettle();

    expect(find.textContaining('CHECK-IN | MED-4'), findsOneWidget);
    expect(find.textContaining('STATUS LOST'), findsOneWidget);
    expect(find.textContaining('DM MED-4'), findsOneWidget);
  });

  testWidgets('filters team users by callsign', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 932);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await login(tester);

    await tester.tap(find.text('Tým'));
    await tester.pumpAndSettle();

    await tester.enterText(_textFieldWithLabel('Vyhledat uživatele'), 'med');
    await tester.pumpAndSettle();

    expect(find.text('MED-4'), findsOneWidget);
    expect(find.text('RAVEN-2'), findsNothing);
  });

  testWidgets('searches direct message recipient', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 932);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await login(tester);

    await tester.tap(find.text('Zprávy'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Osoba'));
    await tester.pumpAndSettle();

    await tester.enterText(_textFieldWithLabel('Vyhledat adresáta'), 'scout');
    await tester.pumpAndSettle();

    expect(find.textContaining('SCOUT-3 / !A1100003'), findsOneWidget);

    await tester.enterText(_textFieldWithHint('Zpráva pro SCOUT-3'), 'Test DM');
    await tester.tap(find.byTooltip('Odeslat přes Meshtastic'));
    await tester.pumpAndSettle();

    expect(find.textContaining('DM SCOUT-3'), findsOneWidget);
    expect(find.text('Test DM'), findsOneWidget);
  });

  testWidgets('sends structured CONTACT report', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 932);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await login(tester);

    await tester.tap(find.text('Zprávy'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('CONTACT'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Odeslat CONTACT'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('CONTACT | MGRS 33U VR 58556 48514'),
      findsOneWidget,
    );
    expect(find.textContaining('DIR 090 | DIST 300 m'), findsOneWidget);
  });

  testWidgets('sends structured MEDEVAC report', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 932);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await login(tester);

    await tester.tap(find.text('Zprávy'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('MEDEVAC'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Odeslat MEDEVAC'));
    await tester.pumpAndSettle();

    expect(find.textContaining('MEDEVAC | WP MED-POINT'), findsOneWidget);
    expect(find.textContaining('33U VR 59048 48110'), findsOneWidget);
  });

  testWidgets('sends structured SITREP report', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 932);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await login(tester);

    await tester.tap(find.text('Zprávy'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('SITREP'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Odeslat SITREP'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('SITREP | MGRS 33U VR 58556 48514'),
      findsOneWidget,
    );
    expect(find.textContaining('TEAM GREEN | BAT 88%'), findsOneWidget);
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

  testWidgets('rejects login with wrong password', (tester) async {
    await tester.pumpWidget(const TacticalCarApp());
    await tester.enterText(find.byType(TextField).first, 'operator');
    await tester.enterText(find.byType(TextField).at(1), 'spatne');
    await tester.tap(find.text('Přihlásit'));
    await tester.pumpAndSettle();

    expect(find.text('Neplatné jméno nebo heslo.'), findsOneWidget);
    expect(find.text('Přihlásit'), findsOneWidget);
  });

  for (final size in const [Size(360, 640), Size(360, 740), Size(740, 360)]) {
    testWidgets(
      'map fits a ${size.width.toInt()}x${size.height.toInt()} phone',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.reset);

        await login(tester);

        expect(tester.takeException(), isNull);
        final mapBox = tester.getRect(find.byType(MeshMap));
        // The map must own most of the body, not a card squeezed by panels.
        expect(mapBox.height, greaterThan(size.height * 0.45));
        expect(find.byKey(const ValueKey('map-details-sheet')), findsOneWidget);
      },
    );
  }

  testWidgets('position readout collapses on small phones and expands on tap', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 640);
    addTearDown(tester.view.reset);

    await login(tester);

    expect(find.byType(PositionChip), findsOneWidget);
    expect(find.byType(CoordinatePanel), findsNothing);

    await tester.tap(find.byKey(const ValueKey('position-panel')));
    await tester.pumpAndSettle();

    expect(find.byType(CoordinatePanel), findsOneWidget);
  });

  testWidgets('details sheet drags up to show metrics', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 640);
    addTearDown(tester.view.reset);

    await login(tester);
    expect(find.text('OK uzly'), findsNothing);

    await tester.drag(
      find.byKey(const ValueKey('map-sheet-handle')),
      const Offset(0, -400),
    );
    await tester.pumpAndSettle();

    expect(find.text('OK uzly'), findsOneWidget);
    expect(find.text('Kanál'), findsOneWidget);
  });

  testWidgets('long press on map creates a waypoint, delete removes it', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 932);
    addTearDown(tester.view.reset);

    await login(tester);

    await tester.longPress(find.byType(MeshMap));
    await tester.pumpAndSettle();
    expect(find.text('Nový bod'), findsOneWidget);

    await tester.tap(find.text('DANGER'));
    await tester.enterText(find.widgetWithText(TextField, 'Kód'), 'mina');
    await tester.tap(find.text('Hned sdílet do skupiny'));
    await tester.tap(find.text('Uložit bod'));
    await tester.pumpAndSettle();

    await tester.drag(
      find.byKey(const ValueKey('map-sheet-handle')),
      const Offset(0, -700),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('delete-waypoint-MINA')),
      200,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('map-details-sheet')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('MINA | DANGER'), findsWidgets);

    final delete = find.byKey(const ValueKey('delete-waypoint-MINA'));
    await tester.ensureVisible(delete);
    await tester.pumpAndSettle();
    await tester.tap(delete);
    await tester.pumpAndSettle();

    expect(find.text('MINA | DANGER'), findsNothing);
  });
}
