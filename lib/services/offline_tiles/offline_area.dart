import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'tile_math.dart';

/// A named offline map pack.
class OfflineArea {
  const OfflineArea({
    required this.id,
    required this.name,
    required this.bounds,
    required this.minZoom,
    required this.maxZoom,
    required this.tileCount,
    required this.createdAt,
    this.complete = true,
  });

  final String id;
  final String name;
  final TileBounds bounds;
  final int minZoom;
  final int maxZoom;

  /// Tiles covering the area (shared tiles are counted in every area).
  final int tileCount;
  final DateTime createdAt;

  /// False when the download was cancelled or some tiles failed.
  final bool complete;

  List<TileKey> get tiles =>
      tilesInBounds(bounds, minZoom: minZoom, maxZoom: maxZoom);

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'bounds': bounds.toJson(),
    'minZoom': minZoom,
    'maxZoom': maxZoom,
    'tileCount': tileCount,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'complete': complete,
  };

  static OfflineArea fromJson(Map<String, dynamic> json) => OfflineArea(
    id: json['id'] as String,
    name: json['name'] as String,
    bounds: TileBounds.fromJson(json['bounds'] as Map<String, dynamic>),
    minZoom: json['minZoom'] as int,
    maxZoom: json['maxZoom'] as int,
    tileCount: json['tileCount'] as int,
    createdAt: DateTime.parse(json['createdAt'] as String),
    complete: json['complete'] != false,
  );
}

/// Where the list of offline areas is kept.
abstract class OfflineAreaRegistry {
  factory OfflineAreaRegistry.preferences(String sourceId) =
      _PreferencesAreaRegistry;

  Future<List<OfflineArea>> load();
  Future<void> save(List<OfflineArea> areas);
}

class _PreferencesAreaRegistry implements OfflineAreaRegistry {
  _PreferencesAreaRegistry(String sourceId) : _key = 'offline.areas.$sourceId';

  final String _key;

  @override
  Future<List<OfflineArea>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) {
        return [];
      }
      return [
        for (final item in jsonDecode(raw) as List)
          OfflineArea.fromJson(item as Map<String, dynamic>),
      ];
    } catch (_) {
      return [];
    }
  }

  @override
  Future<void> save(List<OfflineArea> areas) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _key,
        jsonEncode([for (final area in areas) area.toJson()]),
      );
    } catch (_) {
      // Area list is metadata; tiles stay usable without it.
    }
  }
}

class MemoryOfflineAreaRegistry implements OfflineAreaRegistry {
  List<OfflineArea> areas = [];

  @override
  Future<List<OfflineArea>> load() async => [...areas];

  @override
  Future<void> save(List<OfflineArea> value) async => areas = [...value];
}
