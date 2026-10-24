import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import 'offline_tile_store.dart';
import 'tile_math.dart';
import 'tile_source.dart';

OfflineTileStore createStore(TileSource source) => _UnsupportedTileStore();

/// Web has no file system to keep offline packs in.
class _UnsupportedTileStore implements OfflineTileStore {
  @override
  bool get isSupported => false;

  @override
  int get tileCount => 0;

  @override
  int get sizeBytes => 0;

  @override
  Future<void> init() async {}

  @override
  bool has(TileKey key) => false;

  @override
  ImageProvider? image(TileKey key) => null;

  @override
  Future<void> put(TileKey key, Uint8List bytes) => throw UnsupportedError(
    'Offline maps are not supported on this platform.',
  );

  @override
  Future<void> remove(TileKey key) async {}

  @override
  Future<void> clear() async {}
}
