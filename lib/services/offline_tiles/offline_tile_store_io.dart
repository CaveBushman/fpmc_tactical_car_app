import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import 'offline_tile_store.dart';
import 'tile_math.dart';
import 'tile_source.dart';

OfflineTileStore createStore(TileSource source) =>
    FileOfflineTileStore(source: source);

/// Tiles as files: `<app support>/offline_tiles/<source>/<z>/<x>/<y>.tile`.
/// An in-memory index keeps [has] synchronous for the tile provider.
class FileOfflineTileStore implements OfflineTileStore {
  FileOfflineTileStore({required this.source, this.root});

  final TileSource source;

  /// Base directory; resolved to the app support directory when null.
  Directory? root;
  final Set<TileKey> _index = {};
  int _sizeBytes = 0;
  bool _supported = true;

  @override
  bool get isSupported => _supported;

  @override
  int get tileCount => _index.length;

  @override
  int get sizeBytes => _sizeBytes;

  @override
  Future<void> init() async {
    try {
      root ??= Directory(
        '${(await getApplicationSupportDirectory()).path}/offline_tiles',
      );
      final dir = _sourceDir;
      _index.clear();
      _sizeBytes = 0;
      if (!await dir.exists()) {
        return;
      }
      await for (final entity in dir.list(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.tile')) {
          continue;
        }
        final key = _keyFromPath(entity.path);
        if (key != null) {
          _index.add(key);
          _sizeBytes += await entity.length();
        }
      }
    } catch (_) {
      // No file system access (tests, restricted platforms).
      _supported = false;
    }
  }

  Directory get _sourceDir => Directory('${root!.path}/${source.id}');

  File _file(TileKey key) =>
      File('${_sourceDir.path}/${key.z}/${key.x}/${key.y}.tile');

  TileKey? _keyFromPath(String path) {
    final parts = path.split(Platform.pathSeparator);
    if (parts.length < 3) {
      return null;
    }
    final z = int.tryParse(parts[parts.length - 3]);
    final x = int.tryParse(parts[parts.length - 2]);
    final y = int.tryParse(parts.last.replaceAll('.tile', ''));
    if (z == null || x == null || y == null) {
      return null;
    }
    return TileKey(z, x, y);
  }

  @override
  bool has(TileKey key) => _index.contains(key);

  @override
  ImageProvider? image(TileKey key) =>
      _index.contains(key) ? FileImage(_file(key)) : null;

  @override
  Future<void> put(TileKey key, Uint8List bytes) async {
    if (root == null) {
      throw StateError('OfflineTileStore.init() has not completed.');
    }
    final file = _file(key);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: false);
    if (_index.add(key)) {
      _sizeBytes += bytes.length;
    }
  }

  @override
  Future<void> remove(TileKey key) async {
    if (!_index.remove(key)) {
      return;
    }
    final file = _file(key);
    if (await file.exists()) {
      _sizeBytes -= await file.length();
      await file.delete();
    }
  }

  @override
  Future<void> clear() async {
    if (root != null && await _sourceDir.exists()) {
      await _sourceDir.delete(recursive: true);
    }
    _index.clear();
    _sizeBytes = 0;
  }
}
