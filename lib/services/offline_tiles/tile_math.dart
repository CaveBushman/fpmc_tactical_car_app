import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

/// Slippy-map tile address.
class TileKey {
  const TileKey(this.z, this.x, this.y);

  final int z;
  final int x;
  final int y;

  @override
  bool operator ==(Object other) =>
      other is TileKey && other.z == z && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(z, x, y);

  @override
  String toString() => '$z/$x/$y';
}

int _lonToTileX(double lon, int z) =>
    ((lon + 180) / 360 * (1 << z)).floor().clamp(0, (1 << z) - 1);

int _latToTileY(double lat, int z) {
  final clamped = lat.clamp(-85.05112878, 85.05112878);
  final rad = clamped * math.pi / 180;
  final n = (1 - math.log(math.tan(rad) + 1 / math.cos(rad)) / math.pi) / 2;
  return (n * (1 << z)).floor().clamp(0, (1 << z) - 1);
}

/// Geographic rectangle for tile ranges.
class TileBounds {
  const TileBounds({
    required this.north,
    required this.south,
    required this.west,
    required this.east,
  });

  /// Square of ±[radiusKm] around [center].
  factory TileBounds.around(LatLng center, double radiusKm) {
    final latDelta = radiusKm / 111.32;
    final lonDelta =
        radiusKm / (111.32 * math.cos(center.latitude * math.pi / 180)).abs();
    return TileBounds(
      north: center.latitude + latDelta,
      south: center.latitude - latDelta,
      west: center.longitude - lonDelta,
      east: center.longitude + lonDelta,
    );
  }

  final double north;
  final double south;
  final double west;
  final double east;

  LatLng get center => LatLng((north + south) / 2, (west + east) / 2);

  Map<String, double> toJson() => {
    'north': north,
    'south': south,
    'west': west,
    'east': east,
  };

  static TileBounds fromJson(Map<String, dynamic> json) => TileBounds(
    north: (json['north'] as num).toDouble(),
    south: (json['south'] as num).toDouble(),
    west: (json['west'] as num).toDouble(),
    east: (json['east'] as num).toDouble(),
  );
}

/// Tiles covering [bounds] for every zoom in [minZoom]..[maxZoom], coarse
/// zooms first.
List<TileKey> tilesInBounds(
  TileBounds bounds, {
  required int minZoom,
  required int maxZoom,
}) {
  final tiles = <TileKey>[];
  for (var z = minZoom; z <= maxZoom; z++) {
    final x0 = _lonToTileX(bounds.west, z);
    final x1 = _lonToTileX(bounds.east, z);
    final y0 = _latToTileY(bounds.north, z);
    final y1 = _latToTileY(bounds.south, z);
    for (var x = x0; x <= x1; x++) {
      for (var y = y0; y <= y1; y++) {
        tiles.add(TileKey(z, x, y));
      }
    }
  }
  return tiles;
}

/// Tiles covering a square of ±[radiusKm] around [center].
List<TileKey> tilesAround(
  LatLng center, {
  required double radiusKm,
  required int minZoom,
  required int maxZoom,
}) => tilesInBounds(
  TileBounds.around(center, radiusKm),
  minZoom: minZoom,
  maxZoom: maxZoom,
);
