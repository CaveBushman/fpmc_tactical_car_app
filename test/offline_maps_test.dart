import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:tactical_car_app/controllers/offline_maps_controller.dart';
import 'package:tactical_car_app/services/offline_tiles/offline_first_tile_provider.dart';
import 'package:tactical_car_app/services/offline_tiles/offline_tile_store.dart';
import 'package:tactical_car_app/services/offline_tiles/offline_tile_store_io.dart';
import 'package:tactical_car_app/services/offline_tiles/tile_math.dart';
import 'package:tactical_car_app/services/offline_tiles/tile_source.dart';

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
}
