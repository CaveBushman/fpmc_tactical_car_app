import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tactical_car_app/app.dart';
import 'package:tactical_car_app/controllers/offline_maps_controller.dart';
import 'package:tactical_car_app/services/offline_tiles/offline_area.dart';
import 'package:tactical_car_app/services/offline_tiles/offline_tile_store.dart';
import 'package:tactical_car_app/services/offline_tiles/tile_math.dart';
import 'package:tactical_car_app/services/offline_tiles/tile_source.dart';

import 'support/fakes.dart';

void main() {
  testWidgets('hold-to-confirm wipes data, settings and offline maps', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 932);
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({'settings.nightMode': true});

    final store = MemoryOfflineTileStore();
    await store.put(const TileKey(12, 1, 1), Uint8List(3));
    final maps = OfflineMapsController(
      source: const TileSource(
        id: 't',
        name: 'T',
        urlTemplate: 'https://t/{z}/{x}/{y}.png',
        attribution: 'T',
        allowsBulkDownload: true,
      ),
      store: store,
      areaRegistry: MemoryOfflineAreaRegistry(),
    );

    await tester.pumpWidget(
      TacticalCarApp(
        locationService: FakeLocationService(),
        meshtasticBleService: FakeBleService(),
        offlineMaps: maps,
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'operator');
    await tester.enterText(find.byType(TextField).at(1), 'operator-2026');
    await tester.tap(find.text('Přihlásit'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('night-mode')), findsOneWidget);

    Future<void> openWipeDialog() async {
      await tester.tap(find.byTooltip('Uživatel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nouzově smazat data'));
      await tester.pumpAndSettle();
    }

    // A short press does nothing.
    await openWipeDialog();
    final hold = find.byKey(const ValueKey('wipe-hold'));
    var gesture = await tester.startGesture(tester.getCenter(hold));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('Nouzově smazat data'), findsWidgets);
    expect(store.tileCount, 1);

    // Holding for 3 s wipes.
    gesture = await tester.startGesture(tester.getCenter(hold));
    await tester.pump(); // the animation clock starts on this frame
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.text('Přihlásit'), findsOneWidget);
    expect(store.tileCount, 0);
    expect(find.byKey(const ValueKey('night-mode')), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys().where((k) => k.startsWith('settings.')), isEmpty);
    expect(prefs.getString('tactical_state_v2'), isNull);
  });
}
