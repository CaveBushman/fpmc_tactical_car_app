import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import 'offline_tile_store_stub.dart'
    if (dart.library.io) 'offline_tile_store_io.dart'
    as platform;
import 'tile_math.dart';
import 'tile_source.dart';

/// Permanent tile storage for offline packs. Unlike the HTTP cache these
/// tiles never go stale or get evicted; they are removed only by [clear].
abstract class OfflineTileStore {
  /// Platform default: files under the app support directory, or an
  /// unsupported no-op store on web.
  factory OfflineTileStore.forSource(TileSource source) =>
      platform.createStore(source);

  bool get isSupported;
  int get tileCount;
  int get sizeBytes;

  Future<void> init();
  bool has(TileKey key);

  /// Image for a stored tile, or null when it is not stored.
  ImageProvider? image(TileKey key);
  Future<void> put(TileKey key, Uint8List bytes);
  Future<void> remove(TileKey key);
  Future<void> clear();
}

/// In-memory store for tests.
class MemoryOfflineTileStore implements OfflineTileStore {
  final Map<TileKey, Uint8List> _tiles = {};

  @override
  bool get isSupported => true;

  @override
  int get tileCount => _tiles.length;

  @override
  int get sizeBytes =>
      _tiles.values.fold(0, (sum, bytes) => sum + bytes.length);

  @override
  Future<void> init() async {}

  @override
  bool has(TileKey key) => _tiles.containsKey(key);

  @override
  ImageProvider? image(TileKey key) {
    final bytes = _tiles[key];
    return bytes == null ? null : MemoryImage(bytes);
  }

  @override
  Future<void> put(TileKey key, Uint8List bytes) async => _tiles[key] = bytes;

  @override
  Future<void> remove(TileKey key) async => _tiles.remove(key);

  @override
  Future<void> clear() async => _tiles.clear();
}
