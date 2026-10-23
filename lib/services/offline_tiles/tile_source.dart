/// Where map tiles come from and whether bulk (offline) download is allowed.
class TileSource {
  const TileSource({
    required this.id,
    required this.name,
    required this.urlTemplate,
    required this.attribution,
    this.maxZoom = 18,
    this.allowsBulkDownload = false,
  });

  /// Folder name for this source's offline tiles.
  final String id;
  final String name;

  /// `{z}`, `{x}`, `{y}` placeholders; `{s}` becomes `a`.
  final String urlTemplate;
  final String attribution;
  final int maxZoom;

  /// Public OpenStreetMap tiles forbid bulk downloading
  /// (https://operations.osmfoundation.org/policies/tiles/), so offline
  /// packs need a provider that allows it (own server, MapTiler, …).
  final bool allowsBulkDownload;

  static const openStreetMap = TileSource(
    id: 'osm',
    name: 'OpenStreetMap',
    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    attribution: 'OpenStreetMap',
    maxZoom: 19,
  );

  /// Build-time override, e.g.
  /// `--dart-define=TILE_URL=https://api.maptiler.com/maps/outdoor-v2/{z}/{x}/{y}.png?key=…`
  /// `--dart-define=TILE_NAME=MapTiler --dart-define=TILE_ATTRIBUTION="MapTiler, OpenStreetMap"`.
  /// Falls back to [openStreetMap] when TILE_URL is not set.
  static TileSource fromEnvironment() {
    const url = String.fromEnvironment('TILE_URL');
    if (url.isEmpty) {
      return openStreetMap;
    }
    const name = String.fromEnvironment('TILE_NAME', defaultValue: 'Vlastní');
    const attribution = String.fromEnvironment(
      'TILE_ATTRIBUTION',
      defaultValue: 'OpenStreetMap',
    );
    const maxZoom = int.fromEnvironment('TILE_MAX_ZOOM', defaultValue: 18);
    const allowBulk = bool.fromEnvironment(
      'TILE_ALLOW_BULK',
      defaultValue: true,
    );
    return TileSource(
      id: 'custom-${url.hashCode.toUnsigned(32).toRadixString(16)}',
      name: name,
      urlTemplate: url,
      attribution: attribution,
      maxZoom: maxZoom,
      allowsBulkDownload: allowBulk && !url.contains('tile.openstreetmap.org'),
    );
  }

  String urlFor(int z, int x, int y) => urlTemplate
      .replaceAll('{z}', '$z')
      .replaceAll('{x}', '$x')
      .replaceAll('{y}', '$y')
      .replaceAll('{s}', 'a')
      .replaceAll('{r}', '');
}
