import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:tactical_car_app/controllers/offline_maps_controller.dart';
import 'package:tactical_car_app/services/offline_tiles/offline_area.dart';
import 'package:tactical_car_app/services/offline_tiles/offline_first_tile_provider.dart';
import 'package:tactical_car_app/services/offline_tiles/offline_tile_store.dart';
import 'package:tactical_car_app/services/offline_tiles/offline_tile_store_io.dart';
import 'package:tactical_car_app/services/offline_tiles/tile_math.dart';
import 'package:tactical_car_app/services/offline_tiles/tile_source.dart';
import 'package:tactical_car_app/widgets/offline_maps_section.dart';

const _custom = TileSource(
  id: 'test',
  name: 'Test tiles',
  urlTemplate: 'https://tiles.example.test/{z}/{x}/{y}.png',
  attribution: 'Test',
  maxZoom: 16,
  allowsBulkDownload: true,
);

const _prague = LatLng(50.087451, 14.420671);

class _FakeNetworkProvider extends TileProvider {
  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      const AssetImage('network');
}

void main() {
  group('tile math', () {
    test('covers the centre tile on every zoom, coarse first', () {
      final tiles = tilesAround(_prague, radiusKm: 2, minZoom: 10, maxZoom: 14);
      expect(tiles.first.z, 10);
      expect(tiles.last.z, 14);
      // Known tile for Prague centre at z14.
      expect(tiles, contains(const TileKey(14, 8848, 5550)));
    });

    test('tile count grows with radius', () {
      int count(double km) =>
          tilesAround(_prague, radiusKm: km, minZoom: 10, maxZoom: 16).length;
      expect(count(5), greaterThan(count(2)));
      expect(count(5), lessThan(5000));
    });
  });

  group('tile source', () {
    test('builds tile URLs', () {
      expect(
        _custom.urlFor(14, 8848, 5550),
        'https://tiles.example.test/14/8848/5550.png',
      );
    });

    test('public OSM does not allow bulk download', () {
      expect(TileSource.openStreetMap.allowsBulkDownload, isFalse);
      expect(TileSource.fromEnvironment().id, 'osm');
    });
  });

  group('file store', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('offline_tiles_test');
    });

    tearDown(() async {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });

    test('persists tiles and rebuilds its index from disk', () async {
      final store = FileOfflineTileStore(source: _custom, root: dir);
      await store.init();
      await store.put(const TileKey(12, 2212, 1387), Uint8List(10));

      final reopened = FileOfflineTileStore(source: _custom, root: dir);
      await reopened.init();

      expect(reopened.has(const TileKey(12, 2212, 1387)), isTrue);
      expect(reopened.tileCount, 1);
      expect(reopened.sizeBytes, 10);
      expect(reopened.image(const TileKey(12, 2212, 1387)), isA<FileImage>());

      await reopened.clear();
      expect(reopened.tileCount, 0);
      final again = FileOfflineTileStore(source: _custom, root: dir);
      await again.init();
      expect(again.tileCount, 0);
    });

    test('removes single tiles from disk and index', () async {
      final store = FileOfflineTileStore(source: _custom, root: dir);
      await store.init();
      await store.put(const TileKey(12, 1, 1), Uint8List(4));
      await store.put(const TileKey(12, 1, 2), Uint8List(6));

      await store.remove(const TileKey(12, 1, 1));

      expect(store.has(const TileKey(12, 1, 1)), isFalse);
      expect(store.sizeBytes, 6);
      final reopened = FileOfflineTileStore(source: _custom, root: dir);
      await reopened.init();
      expect(reopened.tileCount, 1);
    });
  });

  test('tile provider prefers stored tiles over the network', () async {
    final store = MemoryOfflineTileStore();
    await store.put(const TileKey(12, 1, 2), Uint8List.fromList([1, 2, 3]));
    final provider = OfflineFirstTileProvider(
      store: store,
      network: _FakeNetworkProvider(),
    );
    final options = TileLayer(urlTemplate: _custom.urlTemplate);

    expect(
      provider.getImage(const TileCoordinates(1, 2, 12), options),
      isA<MemoryImage>(),
    );
    expect(
      provider.getImage(const TileCoordinates(9, 9, 12), options),
      isA<AssetImage>(),
    );
  });

  group('download', () {
    late List<Uri> requests;
    late MemoryOfflineTileStore store;

    OfflineMapsController controllerFor(
      TileSource source, {
      int failEvery = 0,
    }) {
      requests = [];
      store = MemoryOfflineTileStore();
      final client = MockClient((request) async {
        requests.add(request.url);
        if (failEvery > 0 && requests.length % failEvery == 0) {
          return http.Response('nope', 500);
        }
        return http.Response.bytes([7, 7, 7], 200);
      });
      return OfflineMapsController(
        source: source,
        store: store,
        httpClient: client,
      );
    }

    test('refuses bulk download from public OSM', () async {
      final controller = controllerFor(TileSource.openStreetMap);
      await controller.init();

      final started = await controller.downloadAround(_prague, 2);

      expect(started, isFalse);
      expect(requests, isEmpty);
      expect(controller.lastError, contains('nepovoluje'));
    });

    test('downloads only missing tiles and reports progress', () async {
      final controller = controllerFor(_custom);
      await controller.init();
      final expected = controller.tilesFor(_prague, 1);
      await store.put(expected.first, Uint8List(1));
      final fractions = <double>[];
      controller.addListener(() {
        final progress = controller.progress;
        if (progress != null) {
          fractions.add(progress.fraction);
        }
      });

      final started = await controller.downloadAround(_prague, 1);

      expect(started, isTrue);
      expect(requests, hasLength(expected.length - 1));
      expect(requests.first.host, 'tiles.example.test');
      expect(store.tileCount, expected.length);
      expect(controller.estimateMissing(_prague, 1), 0);
      expect(fractions.last, 1.0);
      expect(controller.downloading, isFalse);
      expect(controller.lastError, isNull);
    });

    test('counts failed tiles', () async {
      final controller = controllerFor(_custom, failEvery: 3);
      await controller.init();

      await controller.downloadAround(_prague, 1);

      expect(controller.lastError, contains('nepodařilo'));
      expect(store.tileCount, lessThan(requests.length));
    });

    test('refuses areas over the tile cap', () async {
      final controller = controllerFor(_custom);
      await controller.init();

      final started = await controller.downloadAround(_prague, 200);

      expect(started, isFalse);
      expect(requests, isEmpty);
      expect(controller.lastError, contains('příliš velká'));
    });

    test('cancel stops the download', () async {
      final controller = controllerFor(_custom);
      await controller.init();
      controller.addListener(() {
        if ((controller.progress?.done ?? 0) >= 5) {
          controller.cancelDownload();
        }
      });

      await controller.downloadAround(_prague, 3);

      expect(store.tileCount, lessThan(controller.tilesFor(_prague, 3).length));
      expect(controller.lastError, contains('zrušeno'));
    });
  });

  group('named areas', () {
    late MemoryOfflineTileStore store;
    late MemoryOfflineAreaRegistry registry;
    late int requests;

    OfflineMapsController build() => OfflineMapsController(
      source: _custom,
      store: store,
      areaRegistry: registry,
      httpClient: MockClient((request) async {
        requests++;
        return http.Response.bytes([1, 2, 3], 200);
      }),
    );

    setUp(() {
      store = MemoryOfflineTileStore();
      registry = MemoryOfflineAreaRegistry();
      requests = 0;
    });

    const west = TileBounds(
      north: 50.10,
      south: 50.08,
      west: 14.40,
      east: 14.42,
    );
    const east = TileBounds(
      north: 50.10,
      south: 50.08,
      west: 14.41,
      east: 14.43,
    );

    test('downloads a named area and remembers it', () async {
      final controller = build();
      await controller.init();

      await controller.downloadArea('Most', west);

      final area = controller.areas.single;
      expect(area.name, 'Most');
      expect(area.complete, isTrue);
      expect(area.tileCount, controller.tilesForBounds(west).length);
      expect(store.tileCount, area.tileCount);

      final reloaded = build();
      await reloaded.init();
      expect(reloaded.areas.single.name, 'Most');
    });

    test('deleting an area keeps tiles shared with another area', () async {
      final controller = build();
      await controller.init();
      await controller.downloadArea('Západ', west);
      final requestsBefore = requests;
      await controller.downloadArea('Východ', east);
      expect(
        requests - requestsBefore,
        lessThan(controller.tilesForBounds(east).length),
        reason: 'overlapping tiles are not downloaded twice',
      );

      final westArea = controller.areas.firstWhere((a) => a.name == 'Západ');
      await controller.deleteArea(westArea);

      expect(controller.areas.map((a) => a.name), ['Východ']);
      expect(controller.tilesForBounds(east).every(store.has), isTrue);
      final westOnly = controller
          .tilesForBounds(west)
          .where((tile) => !controller.tilesForBounds(east).contains(tile));
      expect(westOnly, isNotEmpty);
      expect(westOnly.any(store.has), isFalse);
    });

    test('cancelled download is recorded as incomplete', () async {
      final controller = build();
      await controller.init();
      controller.addListener(() {
        if ((controller.progress?.done ?? 0) >= 2) {
          controller.cancelDownload();
        }
      });

      await controller.downloadArea('Velka', TileBounds.around(_prague, 3));

      expect(controller.areas.single.complete, isFalse);
    });

    testWidgets('System section lists areas and downloads the visible one', (
      tester,
    ) async {
      final controller = build();
      await controller.init();
      await controller.downloadArea('Most', west);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: OfflineMapsSection(
                controller: controller,
                center: _prague,
                visibleBounds: east,
              ),
            ),
          ),
        ),
      );

      expect(find.text('Most'), findsOneWidget);
      expect(find.textContaining('Stáhnout zobrazenou oblast'), findsOneWidget);

      await tester.tap(find.textContaining('Stáhnout zobrazenou oblast'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Kopec');
      await tester.tap(find.text('Stáhnout'));
      // The download runs on the test's fake clock; pump until it is done.
      for (var i = 0; i < 100 && controller.areas.length < 2; i++) {
        await tester.pump();
      }
      await tester.pumpAndSettle();

      expect(find.text('Kopec'), findsOneWidget);

      await tester.tap(find.byTooltip('Smazat oblast Most'));
      for (var i = 0; i < 20; i++) {
        await tester.pump();
      }
      expect(find.text('Most'), findsNothing);
    });
  });
}
