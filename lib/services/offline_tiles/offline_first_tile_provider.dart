import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';

import 'offline_tile_store.dart';
import 'tile_math.dart';

/// Serves tiles from the offline store when present and falls back to the
/// network (with flutter_map's HTTP cache) otherwise.
class OfflineFirstTileProvider extends TileProvider {
  OfflineFirstTileProvider({required this.store, TileProvider? network})
    : _network =
          network ??
          NetworkTileProvider(
            cachingProvider: BuiltInMapCachingProvider.getOrCreateInstance(),
          );

  final OfflineTileStore store;
  final TileProvider _network;

  @override
  bool get supportsCancelLoading => _network.supportsCancelLoading;

  ImageProvider? _offline(TileCoordinates coordinates) =>
      store.image(TileKey(coordinates.z, coordinates.x, coordinates.y));

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      _offline(coordinates) ?? _network.getImage(coordinates, options);

  @override
  ImageProvider getImageWithCancelLoadingSupport(
    TileCoordinates coordinates,
    TileLayer options,
    Future<void> cancelLoading,
  ) =>
      _offline(coordinates) ??
      _network.getImageWithCancelLoadingSupport(
        coordinates,
        options,
        cancelLoading,
      );

  @override
  void dispose() {
    _network.dispose();
    super.dispose();
  }
}
