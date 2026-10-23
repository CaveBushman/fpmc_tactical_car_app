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

/// Tiles covering a square of ±[radiusKm] around [center] for every zoom in
/// [minZoom]..[maxZoom], coarse zooms first.
List<TileKey> tilesAround(
  LatLng center, {
  required double radiusKm,
  required int minZoom,
  required int maxZoom,
}) {
  final latDelta = radiusKm / 111.32;
  final lonDelta =
      radiusKm / (111.32 * math.cos(center.latitude * math.pi / 180)).abs();
  final north = center.latitude + latDelta;
  final south = center.latitude - latDelta;
  final west = center.longitude - lonDelta;
  final east = center.longitude + lonDelta;

  final tiles = <TileKey>[];
  for (var z = minZoom; z <= maxZoom; z++) {
    final x0 = _lonToTileX(west, z);
    final x1 = _lonToTileX(east, z);
    final y0 = _latToTileY(north, z);
    final y1 = _latToTileY(south, z);
    for (var x = x0; x <= x1; x++) {
      for (var y = y0; y <= y1; y++) {
        tiles.add(TileKey(z, x, y));
      }
    }
  }
  return tiles;
}
