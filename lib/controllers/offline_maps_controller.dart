import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../services/offline_tiles/offline_area.dart';
import '../services/offline_tiles/offline_tile_store.dart';
import '../services/offline_tiles/tile_math.dart';
import '../services/offline_tiles/tile_source.dart';

class OfflineDownloadProgress {
  const OfflineDownloadProgress({
    required this.total,
    this.done = 0,
    this.failed = 0,
  });

  final int total;
  final int done;
  final int failed;

  double get fraction => total == 0 ? 1 : (done + failed) / total;
}

/// Offline map packs: the tile source, the permanent tile store and
/// downloads of the area around a point.
class OfflineMapsController extends ChangeNotifier {
  OfflineMapsController({
    TileSource? source,
    OfflineTileStore? store,
    OfflineAreaRegistry? areaRegistry,
    http.Client? httpClient,
    this.userAgent = 'first_pmc_tactical_car_app',
    this.concurrency = 4,
  }) : source = source ?? TileSource.fromEnvironment(),
       _httpClient = httpClient ?? http.Client() {
    this.store = store ?? OfflineTileStore.forSource(this.source);
    _registry = areaRegistry ?? OfflineAreaRegistry.preferences(this.source.id);
  }

  static const minZoom = 10;
  static const maxDownloadZoom = 16;

  /// Hard cap so a mistyped radius cannot hammer the tile server or fill
  /// the phone.
  static const maxTilesPerDownload = 25000;

  final TileSource source;
  late final OfflineTileStore store;
  late final OfflineAreaRegistry _registry;
  List<OfflineArea> _areas = [];
  final http.Client _httpClient;
  final String userAgent;
  final int concurrency;

  bool _initialized = false;
  bool _disposed = false;
  bool _cancelRequested = false;
  OfflineDownloadProgress? _progress;
  String? _lastError;

  bool get initialized => _initialized;
  bool get isSupported => store.isSupported;
  bool get canDownload => isSupported && source.allowsBulkDownload;
  bool get downloading => _progress != null;
  OfflineDownloadProgress? get progress => _progress;
  String? get lastError => _lastError;
  int get tileCount => store.tileCount;
  int get sizeBytes => store.sizeBytes;

  /// Named packs, newest first.
  List<OfflineArea> get areas => List.unmodifiable(_areas);

  int get _maxZoom =>
      source.maxZoom < maxDownloadZoom ? source.maxZoom : maxDownloadZoom;

  Future<void> init() async {
    await store.init();
    _areas = await _registry.load();
    _initialized = true;
    _notify();
  }

  List<TileKey> tilesFor(LatLng center, double radiusKm) => tilesAround(
    center,
    radiusKm: radiusKm,
    minZoom: minZoom,
    maxZoom: _maxZoom,
  );

  /// Tiles still missing for the area (what a download would fetch).
  int estimateMissing(LatLng center, double radiusKm) =>
      tilesFor(center, radiusKm).where((tile) => !store.has(tile)).length;

  List<TileKey> tilesForBounds(TileBounds bounds) =>
      tilesInBounds(bounds, minZoom: minZoom, maxZoom: _maxZoom);

  int estimateMissingIn(TileBounds bounds) =>
      tilesForBounds(bounds).where((tile) => !store.has(tile)).length;

  /// Downloads the area around [center] as a pack named after the radius.
  Future<bool> downloadAround(LatLng center, double radiusKm) => downloadArea(
    'Okolí ${radiusKm.toStringAsFixed(0)} km',
    TileBounds.around(center, radiusKm),
  );

  /// Downloads missing tiles in [bounds] and records it as a named area.
  /// Returns false when the download was refused (unsupported, not
  /// allowed, too large, busy).
  Future<bool> downloadArea(String name, TileBounds bounds) async {
    final trimmed = name.trim().isEmpty ? 'Oblast' : name.trim();
    final all = tilesForBounds(bounds);
    final ok = await _downloadTiles(all);
    if (!ok) {
      return false;
    }
    final now = DateTime.now();
    _areas = [
      OfflineArea(
        id: now.microsecondsSinceEpoch.toRadixString(36),
        name: trimmed,
        bounds: bounds,
        minZoom: minZoom,
        maxZoom: _maxZoom,
        tileCount: all.length,
        createdAt: now,
        complete: all.every(store.has),
      ),
      ..._areas,
    ];
    await _registry.save(_areas);
    _notify();
    return true;
  }

  /// Removes [area] and the tiles no other area needs.
  Future<void> deleteArea(OfflineArea area) async {
    if (downloading) {
      return;
    }
    final keep = <TileKey>{
      for (final other in _areas)
        if (other.id != area.id) ...other.tiles,
    };
    for (final tile in area.tiles) {
      if (!keep.contains(tile)) {
        await store.remove(tile);
      }
    }
    _areas = [
      for (final other in _areas)
        if (other.id != area.id) other,
    ];
    await _registry.save(_areas);
    _notify();
  }

  Future<bool> _downloadTiles(List<TileKey> tiles) async {
    _lastError = null;
    if (downloading) {
      return false;
    }
    if (!isSupported) {
      _setError('Offline mapy nejsou na tomto zařízení podporované.');
      return false;
    }
    if (!source.allowsBulkDownload) {
      _setError(
        'Zdroj ${source.name} hromadné stahování nepovoluje. '
        'Nastav vlastní zdroj dlaždic (TILE_URL).',
      );
      return false;
    }
    final missing = tiles.where((tile) => !store.has(tile)).toList();
    if (missing.length > maxTilesPerDownload) {
      _setError(
        'Oblast je příliš velká (${missing.length} dlaždic, '
        'max $maxTilesPerDownload). Zmenši oblast.',
      );
      return false;
    }

    _cancelRequested = false;
    var done = 0;
    var failed = 0;
    _progress = OfflineDownloadProgress(total: missing.length);
    _notify();

    var next = 0;
    Future<void> worker() async {
      while (!_cancelRequested && !_disposed && next < missing.length) {
        final tile = missing[next++];
        try {
          final response = await _httpClient.get(
            Uri.parse(source.urlFor(tile.z, tile.x, tile.y)),
            headers: {'User-Agent': userAgent},
          );
          if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
            await store.put(tile, response.bodyBytes);
            done++;
          } else {
            failed++;
          }
        } catch (_) {
          failed++;
        }
        _progress = OfflineDownloadProgress(
          total: missing.length,
          done: done,
          failed: failed,
        );
        _notify();
      }
    }

    await Future.wait([for (var i = 0; i < concurrency; i++) worker()]);
    if (failed > 0) {
      _lastError = '$failed dlaždic se nepodařilo stáhnout.';
    }
    if (_cancelRequested) {
      _lastError = 'Stahování zrušeno ($done/${missing.length}).';
    }
    _progress = null;
    _notify();
    return true;
  }

  void cancelDownload() {
    if (downloading) {
      _cancelRequested = true;
    }
  }

  Future<void> clear() async {
    cancelDownload();
    await store.clear();
    _areas = [];
    await _registry.save(_areas);
    _lastError = null;
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelRequested = true;
    _httpClient.close();
    super.dispose();
  }

  void _setError(String message) {
    _lastError = message;
    _notify();
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }
}
