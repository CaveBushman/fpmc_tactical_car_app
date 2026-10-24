import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/member_status.dart';
import '../models/mesh_node.dart';
import '../models/navigation.dart';
import '../services/location_service.dart';
import '../services/offline_tiles/offline_first_tile_provider.dart';
import '../services/offline_tiles/offline_tile_store.dart';
import '../services/offline_tiles/tile_math.dart';
import '../services/offline_tiles/tile_source.dart';
import '../theme.dart';
import '../widgets/common_widgets.dart';
import '../widgets/mgrs_grid_layer.dart';
import '../widgets/navigation_widgets.dart';
import '../widgets/node_widgets.dart';
import '../widgets/position_widgets.dart';

/// Full-bleed map. Position readout floats top-left; team metrics, navigation
/// targets and waypoints live in a bottom sheet that peeks with the nearest
/// target and drags up for the rest, so small phones keep most of the screen
/// for the map.
class MapPage extends StatefulWidget {
  const MapPage({
    required this.nodes,
    required this.waypoints,
    required this.pttActive,
    required this.onShareWaypoint,
    this.onCreateWaypoint,
    this.onDeleteWaypoint,
    this.tileSource = TileSource.openStreetMap,
    this.offlineStore,
    this.onVisibleBoundsChanged,
    this.track = const [],
    this.showGrid = true,
    this.onSharePoint,
    this.locationState = LocationState.idle,
    this.channelLabel = 'ALPHA',
    this.showDetailsSheet = true,
    this.navTarget,
    this.onNavigate,
    this.onClearNavTarget,
    this.peerTrails = const {},
    this.onClearOldWaypoints,
    this.speedKmh = TacticalNavSolution.walkingKmh,
    this.courseDeg,
    this.headingUp = false,
    this.onHeadingUpChanged,
    this.statusOf,
    super.key,
  });

  /// Peers' reported status by callsign.
  final MemberStatus? Function(String callSign)? statusOf;

  /// Teammates' recent positions by node number.
  final Map<int, List<LatLng>> peerTrails;

  /// Deletes received points older than 6 h; returns how many.
  final int Function()? onClearOldWaypoints;

  /// Own speed for ETAs.
  final double speedKmh;

  /// Own direction of travel (GPS course), null before moving.
  final double? courseDeg;
  final bool headingUp;
  final ValueChanged<bool>? onHeadingUpChanged;

  final List<MeshNode> nodes;
  final List<TacticalWaypoint> waypoints;
  final bool pttActive;
  final ValueChanged<TacticalWaypoint> onShareWaypoint;
  final ValueChanged<WaypointDraft>? onCreateWaypoint;
  final ValueChanged<TacticalWaypoint>? onDeleteWaypoint;
  final TileSource tileSource;
  final OfflineTileStore? offlineStore;
  final ValueChanged<TileBounds>? onVisibleBoundsChanged;
  final List<LatLng> track;
  final bool showGrid;

  /// Sends an inspected map point to the group.
  final ValueChanged<LatLng>? onSharePoint;
  final LocationState locationState;
  final String channelLabel;

  /// False when the map sits next to another panel (landscape detail tabs).
  final bool showDetailsSheet;

  /// Chosen navigation target (live), drawn as a line and shown instead of
  /// the nearest target.
  final TacticalNavSolution? navTarget;
  final ValueChanged<NavTarget>? onNavigate;
  final VoidCallback? onClearNavTarget;

  /// Height of the collapsed sheet (handle + nearest-target row) at the
  /// default font size.
  static const sheetPeekHeight = 76.0;

  /// [sheetPeekHeight] grown with the font size, so the row fits.
  static double peekHeightFor(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(sheetPeekHeight);

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  bool? _positionExpanded;

  /// Point tapped on the map, shown in an info card.
  LatLng? _inspected;

  /// Point entered by hand that the map should move to.
  LatLng? _focus;

  /// Measuring mode: taps add points instead of opening the point card.
  List<LatLng>? _measure;

  void _onMapTap(LatLng point) {
    final measure = _measure;
    setState(() {
      if (measure != null) {
        _measure = [...measure, point];
      } else {
        _inspected = point;
      }
    });
  }

  Future<void> _createWaypointAt(
    LatLng point, {
    TacticalWaypoint? editing,
  }) async {
    final draft = await showModalBottomSheet<WaypointDraft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: panelGreen,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
      ),
      builder: (context) =>
          WaypointEditorSheet(position: point, editing: editing),
    );
    if (draft != null) {
      widget.onCreateWaypoint?.call(draft);
    }
  }

  Future<void> _confirmClearOld() async {
    final now = DateTime.now();
    final count = widget.waypoints.where((w) => w.isOldReceivedAt(now)).length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        backgroundColor: panelGreen,
        title: const Text('Smazat staré přijaté body?'),
        content: Text(
          'Smaže body od ostatních starší než 6 h (počet: $count). '
          'Vlastní body zůstanou.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Zrušit'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Smazat'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      widget.onClearOldWaypoints?.call();
    }
  }

  Future<void> _enterCoordinates(LatLng near) async {
    final point = await showDialog<LatLng>(
      context: context,
      builder: (context) => CoordinateEntryDialog(near: near),
    );
    if (point != null && mounted) {
      setState(() {
        _focus = point;
        _inspected = point;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final nodes = widget.nodes;
    final self = nodes.firstWhere((node) => node.isSelf);
    final navSolutions = TacticalNavSolution.fromMission(
      self: self,
      nodes: nodes,
      waypoints: widget.waypoints,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        final narrow = constraints.maxWidth < 420;
        // Expanded readout only where it does not bury the map; the user can
        // still toggle it.
        final positionExpanded = _positionExpanded ?? height >= 640;
        final showSheet = widget.showDetailsSheet && height >= 240;
        final peekHeight = MapPage.peekHeightFor(context);
        final mapBottom = showSheet ? peekHeight - 8 : 0.0;
        // Ruler, coordinates and recenter buttons.
        final cardLeft = MeshMap.cardLeft(height - mapBottom, 3);
        final cardBottom = (showSheet ? peekHeight : 0.0) + 8;

        return Stack(
          children: [
            Positioned(
              left: 0,
              top: 0,
              right: 0,
              bottom: mapBottom,
              child: MeshMap(
                key: const ValueKey('mesh-map'),
                nodes: nodes,
                waypoints: widget.waypoints,
                onLongPress: widget.onCreateWaypoint == null
                    ? null
                    : _createWaypointAt,
                tileSource: widget.tileSource,
                offlineStore: widget.offlineStore,
                onVisibleBoundsChanged: widget.onVisibleBoundsChanged,
                track: widget.track,
                showGrid: widget.showGrid,
                navTarget: widget.navTarget?.position,
                focus: _focus,
                onEnterCoordinates: () => _enterCoordinates(self.latLng),
                peerTrails: widget.peerTrails,
                courseDeg: widget.courseDeg,
                statusOf: widget.statusOf,
                headingUp: widget.headingUp,
                onHeadingUpChanged: widget.onHeadingUpChanged,
                measure: _measure ?? const [],
                measuring: _measure != null,
                onToggleMeasure: () => setState(() {
                  _measure = _measure == null ? [] : null;
                  _inspected = null;
                }),
                onTap: _onMapTap,
              ),
            ),
            if (_measure case final measure?)
              Positioned(
                left: cardLeft,
                right: 8,
                bottom: cardBottom,
                child: _FitAboveSheet(
                  maxHeight: height - cardBottom - 8,
                  child: MeasurePanel(
                    points: measure,
                    onFromSelf: () =>
                        setState(() => _measure = [self.latLng, ...measure]),
                    onUndo: () => setState(
                      () => _measure = measure.sublist(0, measure.length - 1),
                    ),
                    onClose: () => setState(() => _measure = null),
                  ),
                ),
              )
            else if (_inspected != null)
              Positioned(
                left: cardLeft,
                right: 8,
                bottom: cardBottom,
                child: _FitAboveSheet(
                  maxHeight: height - cardBottom - 8,
                  child: PointInfoCard(
                    point: _inspected!,
                    from: self.latLng,
                    onClose: () => setState(() => _inspected = null),
                    onSave: widget.onCreateWaypoint == null
                        ? null
                        : () {
                            final point = _inspected!;
                            setState(() => _inspected = null);
                            _createWaypointAt(point);
                          },
                    onShare: widget.onSharePoint == null
                        ? null
                        : () {
                            widget.onSharePoint!(_inspected!);
                            setState(() => _inspected = null);
                          },
                    onNavigate: widget.onNavigate == null
                        ? null
                        : () {
                            widget.onNavigate!(NavTarget.point(_inspected!));
                            setState(() => _inspected = null);
                          },
                  ),
                ),
              ),
            Positioned(
              left: 8,
              top: 8,
              right: narrow ? 56 : null,
              child: GestureDetector(
                key: const ValueKey('position-panel'),
                behavior: HitTestBehavior.opaque,
                onTap: () =>
                    setState(() => _positionExpanded = !positionExpanded),
                child: positionExpanded
                    ? CoordinatePanel(
                        node: self,
                        locationState: widget.locationState,
                        compact: narrow,
                      )
                    : PositionChip(
                        node: self,
                        locationState: widget.locationState,
                      ),
              ),
            ),
            if (showSheet)
              _MapDetailsSheet(
                peekFraction: (peekHeight / height).clamp(0.05, 0.5),
                nodes: nodes,
                navSolutions: navSolutions,
                waypoints: widget.waypoints,
                pttActive: widget.pttActive,
                channelLabel: widget.channelLabel,
                onShareWaypoint: widget.onShareWaypoint,
                onDeleteWaypoint: widget.onDeleteWaypoint,
                speedKmh: widget.speedKmh,
                onClearOld: widget.onClearOldWaypoints == null
                    ? null
                    : _confirmClearOld,
                onEditWaypoint: widget.onCreateWaypoint == null
                    ? null
                    : (waypoint) =>
                          _createWaypointAt(waypoint.latLng, editing: waypoint),
                navTarget: widget.navTarget,
                onNavigate: widget.onNavigate,
                onClearNavTarget: widget.onClearNavTarget,
              ),
          ],
        );
      },
    );
  }
}

class _MapDetailsSheet extends StatelessWidget {
  const _MapDetailsSheet({
    required this.peekFraction,
    required this.nodes,
    required this.navSolutions,
    required this.waypoints,
    required this.pttActive,
    required this.channelLabel,
    required this.onShareWaypoint,
    this.onDeleteWaypoint,
    this.onEditWaypoint,
    this.onClearOld,
    this.navTarget,
    this.onNavigate,
    this.onClearNavTarget,
    this.speedKmh = TacticalNavSolution.walkingKmh,
  });

  final double speedKmh;
  final VoidCallback? onClearOld;
  final ValueChanged<TacticalWaypoint>? onEditWaypoint;
  final TacticalNavSolution? navTarget;
  final ValueChanged<NavTarget>? onNavigate;
  final VoidCallback? onClearNavTarget;
  final double peekFraction;
  final List<MeshNode> nodes;
  final List<TacticalNavSolution> navSolutions;
  final List<TacticalWaypoint> waypoints;
  final bool pttActive;
  final String channelLabel;
  final ValueChanged<TacticalWaypoint> onShareWaypoint;
  final ValueChanged<TacticalWaypoint>? onDeleteWaypoint;

  @override
  Widget build(BuildContext context) {
    final health = NodeHealthSummary.fromNodes(nodes);
    final nearest = navSolutions.isEmpty ? null : navSolutions.first;
    return DraggableScrollableSheet(
      key: const ValueKey('map-details-sheet'),
      initialChildSize: peekFraction,
      minChildSize: peekFraction,
      maxChildSize: 0.88,
      snap: true,
      snapSizes: [peekFraction, 0.5],
      builder: (context, scrollController) {
        return DecoratedBox(
          decoration: BoxDecoration(
            color: panelGreen,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 12)],
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
            children: [
              Center(
                child: Container(
                  key: const ValueKey('map-sheet-handle'),
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              SizedBox(
                height: MediaQuery.textScalerOf(context).scale(52),
                child: Row(
                  children: [
                    Expanded(
                      child: navTarget != null
                          ? NavigationCueBadge(
                              solution: navTarget!,
                              onClear: onClearNavTarget ?? () {},
                            )
                          : nearest == null
                          ? const SizedBox.shrink()
                          : NavigationCueBadge(solution: nearest),
                    ),
                    const SizedBox(width: 8),
                    _HealthDots(health: health),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              GridView(
                // Fixed tile height (scaled with the font setting) instead of
                // an aspect ratio, which collapses on narrow phones.
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: MediaQuery.sizeOf(context).width > 640
                      ? 4
                      : 2,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  mainAxisExtent: MediaQuery.textScalerOf(context).scale(68),
                ),
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  MetricTile(
                    label: 'OK uzly',
                    value: '${health.ok}/${nodes.length}',
                    icon: Icons.hub_outlined,
                  ),
                  MetricTile(
                    label: 'Kanál',
                    value: channelLabel,
                    icon: Icons.radio,
                  ),
                  MetricTile(
                    label: 'Stale / Lost',
                    value: '${health.stale} / ${health.lost}',
                    icon: Icons.schedule_outlined,
                  ),
                  MetricTile(
                    label: 'Nejbližší',
                    value: _nearestLabel(nodes),
                    icon: Icons.near_me_outlined,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              NavigationTargetStrip(
                solutions: navSolutions,
                onShareWaypoint: onShareWaypoint,
                onNavigate: onNavigate,
                speedKmh: speedKmh,
              ),
              const SizedBox(height: 10),
              WaypointStrip(
                waypoints: waypoints,
                onShareWaypoint: onShareWaypoint,
                onDeleteWaypoint: onDeleteWaypoint,
                onEditWaypoint: onEditWaypoint,
                onClearOld: onClearOld,
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: MapLegend(pttActive: pttActive),
              ),
            ],
          ),
        );
      },
    );
  }

  String _nearestLabel(List<MeshNode> nodes) {
    final others = nodes.where((node) => !node.isSelf).toList()
      ..sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
    if (others.isEmpty) {
      return '-';
    }
    return '${others.first.distanceKm.toStringAsFixed(1)} km';
  }
}

/// OK / STALE / LOST counts as three small coloured numbers.
class _HealthDots extends StatelessWidget {
  const _HealthDots({required this.health});

  final NodeHealthSummary health;

  @override
  Widget build(BuildContext context) {
    Widget dot(MeshNodeLinkStatus status, int count) => Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Tooltip(
        message: '${status.label}: $count',
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.circle, size: 10, color: status.color),
            const SizedBox(width: 3),
            Text(
              '$count',
              style: TextStyle(
                color: status.color,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        dot(MeshNodeLinkStatus.ok, health.ok),
        dot(MeshNodeLinkStatus.stale, health.stale),
        dot(MeshNodeLinkStatus.lost, health.lost),
      ],
    );
  }
}

class MeshMap extends StatefulWidget {
  const MeshMap({
    required this.nodes,
    required this.waypoints,
    this.onLongPress,
    this.tileSource = TileSource.openStreetMap,
    this.offlineStore,
    this.onVisibleBoundsChanged,
    this.track = const [],
    this.showGrid = true,
    this.onTap,
    this.navTarget,
    this.focus,
    this.onEnterCoordinates,
    this.peerTrails = const {},
    this.measure = const [],
    this.measuring = false,
    this.onToggleMeasure,
    this.courseDeg,
    this.headingUp = false,
    this.onHeadingUpChanged,
    this.statusOf,
    super.key,
  });

  /// Peers' reported status by callsign.
  final MemberStatus? Function(String callSign)? statusOf;

  /// Own direction of travel; turns the self arrow (and the map when
  /// [headingUp]).
  final double? courseDeg;

  /// Direction of travel up instead of north up, while following self.
  final bool headingUp;

  /// Shows the compass button that switches [headingUp].
  final ValueChanged<bool>? onHeadingUpChanged;

  /// Teammates' recent positions, drawn as faint dotted lines.
  final Map<int, List<LatLng>> peerTrails;

  /// Measured path (drawn while [measuring]).
  final List<LatLng> measure;
  final bool measuring;

  /// Shows the ruler button.
  final VoidCallback? onToggleMeasure;

  static const controlsBottom = 36.0;
  static const _controlStep = 56.0;

  /// Room kept free at the top for the position panel.
  static const _controlsTopReserve = 120.0;

  /// Whether [count] bottom-left buttons fit in a column on a map this
  /// high; otherwise they line up along the bottom edge.
  static bool controlsFitColumn(double mapHeight, int count) =>
      controlsBottom + count * _controlStep + _controlsTopReserve <= mapHeight;

  /// Left edge for cards floating over the map bottom, right of the
  /// buttons so they never cover them.
  static double cardLeft(double mapHeight, int count) =>
      controlsFitColumn(mapHeight, count) ? 72 : 12 + count * _controlStep + 4;

  /// Moves the map here whenever it changes (stops following self).
  final LatLng? focus;

  /// Shows a button that opens the coordinate entry.
  final VoidCallback? onEnterCoordinates;

  final List<MeshNode> nodes;
  final List<TacticalWaypoint> waypoints;
  final ValueChanged<LatLng>? onLongPress;

  /// Chosen navigation target: dashed line from self.
  final LatLng? navTarget;

  /// MGRS/UTM grid overlay.
  final bool showGrid;
  final ValueChanged<LatLng>? onTap;

  /// Own recorded trail, drawn under the markers.
  final List<LatLng> track;

  /// Reports the area on screen (used to download it for offline use).
  final ValueChanged<TileBounds>? onVisibleBoundsChanged;
  final TileSource tileSource;

  /// Offline packs to prefer over the network; null = network only.
  final OfflineTileStore? offlineStore;

  @override
  State<MeshMap> createState() => _MeshMapState();
}

class _MeshMapState extends State<MeshMap> {
  final MapController _mapController = MapController();

  // One provider per map: TileLayer disposes it together with the map.
  late final TileProvider _tileProvider = widget.offlineStore == null
      ? NetworkTileProvider(
          cachingProvider: BuiltInMapCachingProvider.getOrCreateInstance(),
        )
      : OfflineFirstTileProvider(store: widget.offlineStore!);
  bool _mapReady = false;
  bool _followSelf = true;
  LatLng? _lastSelfPoint;
  LatLng? _lastFocus;
  double _rotation = 0;

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  ButtonStyle _controlStyle({required bool active}) => IconButton.styleFrom(
    backgroundColor: active
        ? rangerGreen
        : Colors.black.withValues(alpha: 0.76),
    foregroundColor: active ? Colors.white : sand,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
  );

  void _recenter() {
    setState(() => _followSelf = true);
    if (_mapReady) {
      final self = widget.nodes.firstWhere((node) => node.isSelf);
      _mapController.move(self.latLng, _mapController.camera.zoom);
    }
  }

  @override
  Widget build(BuildContext context) {
    final nodes = widget.nodes;
    final waypoints = widget.waypoints;
    final self = nodes.firstWhere((node) => node.isSelf);
    final selfPoint = self.latLng;
    // The node list is mutated in place by the parent, so compare against the
    // last rendered position rather than oldWidget in didUpdateWidget.
    if (_lastSelfPoint != selfPoint) {
      _lastSelfPoint = selfPoint;
      if (_followSelf && _mapReady) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _followSelf) {
            _mapController.move(selfPoint, _mapController.camera.zoom);
          }
        });
      }
    }
    // Heading up only while following our own position; looking around
    // the map (or north-up mode) keeps north up.
    final course = widget.courseDeg;
    final rotation = widget.headingUp && _followSelf && course != null
        ? -course
        : 0.0;
    if (rotation != _rotation) {
      _rotation = rotation;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _mapReady) {
          _mapController.rotate(rotation);
        }
      });
    }
    // Marker boxes grow with the font size so their labels fit.
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final focus = widget.focus;
    if (focus != null && focus != _lastFocus) {
      _lastFocus = focus;
      _followSelf = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _mapReady) {
          _mapController.move(focus, _mapController.camera.zoom);
        }
      });
    }
    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: selfPoint,
            initialZoom: 13.4,
            onMapReady: () => _mapReady = true,
            onLongPress: widget.onLongPress == null
                ? null
                : (_, point) => widget.onLongPress!(point),
            onTap: widget.onTap == null
                ? null
                : (_, point) => widget.onTap!(point),
            onPositionChanged: (camera, hasGesture) {
              final bounds = camera.visibleBounds;
              widget.onVisibleBoundsChanged?.call(
                TileBounds(
                  north: bounds.north,
                  south: bounds.south,
                  west: bounds.west,
                  east: bounds.east,
                ),
              );
              if (hasGesture && _followSelf) {
                setState(() => _followSelf = false);
              }
            },
            minZoom: 3,
            maxZoom: 18,
            backgroundColor: fieldBlack,
            interactionOptions: const InteractionOptions(
              flags:
                  InteractiveFlag.drag |
                  InteractiveFlag.flingAnimation |
                  InteractiveFlag.pinchMove |
                  InteractiveFlag.pinchZoom |
                  InteractiveFlag.doubleTapZoom |
                  InteractiveFlag.scrollWheelZoom,
            ),
          ),
          children: [
            TileLayer(
              urlTemplate: widget.tileSource.urlTemplate,
              maxNativeZoom: widget.tileSource.maxZoom,
              userAgentPackageName: 'first_pmc_tactical_car_app',
              tileProvider: _tileProvider,
              tileBuilder: _tacticalTileBuilder,
            ),
            if (widget.showGrid) const MgrsGridLayer(),
            PolylineLayer(
              polylines: [
                if (widget.track.length > 1)
                  Polyline(
                    points: [...widget.track, selfPoint],
                    strokeWidth: 3,
                    color: sand.withValues(alpha: 0.75),
                    borderStrokeWidth: 1,
                    borderColor: Colors.black.withValues(alpha: 0.5),
                  ),
                for (final trail in widget.peerTrails.values)
                  Polyline(
                    points: trail,
                    strokeWidth: 2,
                    color: blueForce.withValues(alpha: 0.55),
                    pattern: const StrokePattern.dotted(spacingFactor: 2),
                  ),
                if (widget.measure.length > 1)
                  Polyline(
                    points: widget.measure,
                    strokeWidth: 3,
                    color: Colors.white,
                    borderStrokeWidth: 1.5,
                    borderColor: Colors.black.withValues(alpha: 0.7),
                  ),
                if (widget.navTarget case final target?)
                  Polyline(
                    points: [selfPoint, target],
                    strokeWidth: 4,
                    color: signalAmber,
                    borderStrokeWidth: 1.5,
                    borderColor: Colors.black.withValues(alpha: 0.6),
                    pattern: StrokePattern.dashed(segments: const [14, 8]),
                  ),
                for (final node in nodes.where((node) => !node.isSelf))
                  Polyline(
                    points: [selfPoint, node.latLng],
                    strokeWidth: 1.2,
                    color: blueForce.withValues(alpha: 0.42),
                    borderStrokeWidth: 0.6,
                    borderColor: Colors.black.withValues(alpha: 0.32),
                  ),
              ],
            ),
            CircleLayer(
              circles: [
                for (final point in widget.measure)
                  CircleMarker(
                    point: point,
                    radius: 5,
                    color: Colors.white,
                    borderColor: Colors.black,
                    borderStrokeWidth: 1.5,
                  ),
                CircleMarker(
                  point: selfPoint,
                  radius: 1200,
                  useRadiusInMeter: true,
                  color: tacticalKhaki.withValues(alpha: 0.05),
                  borderColor: tacticalKhaki.withValues(alpha: 0.18),
                  borderStrokeWidth: 1,
                ),
                CircleMarker(
                  point: selfPoint,
                  radius: 2400,
                  useRadiusInMeter: true,
                  color: Colors.transparent,
                  borderColor: tacticalKhaki.withValues(alpha: 0.14),
                  borderStrokeWidth: 1,
                ),
              ],
            ),
            MarkerLayer(
              // Labels stay upright when the map is turned.
              rotate: true,
              markers: [
                for (final waypoint in waypoints)
                  Marker(
                    point: waypoint.latLng,
                    width: 112 * textScale,
                    height: 66 * textScale,
                    // Old information steps back behind fresh reports.
                    child: Opacity(
                      opacity: waypoint.isStaleAt(DateTime.now()) ? 0.45 : 1,
                      child: WaypointMapMarker(waypoint: waypoint),
                    ),
                  ),
                for (final node in nodes)
                  Marker(
                    point: node.latLng,
                    width: 92 * textScale,
                    height: 64 * textScale,
                    child: node.isSelf
                        ? Builder(
                            // Arrow relative to the screen: course plus the
                            // map's own rotation.
                            builder: (context) => MapNodeMarker(
                              node: node,
                              arrowDeg: course == null
                                  ? null
                                  : course + MapCamera.of(context).rotation,
                            ),
                          )
                        : MapNodeMarker(
                            node: node,
                            memberStatus: widget.statusOf?.call(node.callSign),
                          ),
                  ),
              ],
            ),
            RichAttributionWidget(
              attributions: [
                TextSourceAttribution(widget.tileSource.attribution),
              ],
              alignment: AttributionAlignment.bottomLeft,
            ),
          ],
        ),
        if (widget.onHeadingUpChanged != null)
          Positioned(
            right: 8,
            top: 8,
            child: IconButton.filled(
              key: const ValueKey('heading-up'),
              tooltip: widget.headingUp
                  ? 'Směr jízdy nahoře (klepni pro sever)'
                  : 'Sever nahoře (klepni pro směr jízdy)',
              onPressed: () => widget.onHeadingUpChanged!(!widget.headingUp),
              style: IconButton.styleFrom(
                backgroundColor: widget.headingUp
                    ? rangerGreen
                    : Colors.black.withValues(alpha: 0.76),
                foregroundColor: widget.headingUp ? Colors.white : sand,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              // The needle points to north on screen.
              icon: Transform.rotate(
                angle: rotation * math.pi / 180,
                child: const Icon(Icons.navigation),
              ),
            ),
          ),
        // Ruler, coordinate entry and recenter stacked bottom-left; on a
        // short map (phone in landscape) the column would run into the
        // position panel, so they line up along the bottom instead.
        Positioned.fill(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final buttons = [
                if (widget.onToggleMeasure != null)
                  IconButton.filled(
                    key: const ValueKey('measure'),
                    tooltip: widget.measuring ? 'Ukončit měření' : 'Měřit',
                    onPressed: widget.onToggleMeasure,
                    style: _controlStyle(active: widget.measuring),
                    icon: const Icon(Icons.straighten),
                  ),
                if (widget.onEnterCoordinates != null)
                  IconButton.filled(
                    key: const ValueKey('enter-coordinates'),
                    tooltip: 'Zadat souřadnice',
                    onPressed: widget.onEnterCoordinates,
                    style: _controlStyle(active: false),
                    icon: const Icon(Icons.edit_location_alt_outlined),
                  ),
                IconButton.filled(
                  key: const ValueKey('recenter'),
                  tooltip: _followSelf
                      ? 'Mapa sleduje vlastní pozici'
                      : 'Vycentrovat na vlastní pozici',
                  onPressed: _recenter,
                  style: _controlStyle(active: _followSelf),
                  icon: Icon(
                    _followSelf ? Icons.my_location : Icons.location_searching,
                  ),
                ),
              ];
              const bottom = MeshMap.controlsBottom;
              final fitsColumn = MeshMap.controlsFitColumn(
                constraints.maxHeight,
                buttons.length,
              );
              return Stack(
                children: [
                  Positioned(
                    left: 12,
                    bottom: bottom,
                    child: Flex(
                      direction: fitsColumn ? Axis.vertical : Axis.horizontal,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final (index, button) in buttons.indexed) ...[
                          if (index > 0) const SizedBox(width: 8, height: 8),
                          button,
                        ],
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

Widget _tacticalTileBuilder(
  BuildContext context,
  Widget tileWidget,
  TileImage tile,
) {
  return ColorFiltered(
    colorFilter: const ColorFilter.matrix([
      0.62,
      0.18,
      0.10,
      0,
      -18,
      0.12,
      0.58,
      0.12,
      0,
      -16,
      0.10,
      0.18,
      0.50,
      0,
      -18,
      0,
      0,
      0,
      1,
      0,
    ]),
    child: Opacity(opacity: 0.86, child: tileWidget),
  );
}

class MapNodeMarker extends StatelessWidget {
  const MapNodeMarker({
    required this.node,
    this.arrowDeg,
    this.memberStatus,
    super.key,
  });

  final MeshNode node;

  /// Reported status; replaces the link label when it is not OK.
  final MemberStatus? memberStatus;

  /// Self only: direction of travel on screen (0 = up); null = no course.
  final double? arrowDeg;

  @override
  Widget build(BuildContext context) {
    final color = node.isSelf ? tacticalKhaki : node.linkStatus.color;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          height: node.isSelf ? 22 : 18,
          width: node.isSelf ? 22 : 18,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.black, width: 2),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.35),
                blurRadius: 12,
                spreadRadius: 3,
              ),
            ],
          ),
          child: node.isSelf
              ? Transform.rotate(
                  angle: (arrowDeg ?? 0) * math.pi / 180,
                  child: const Icon(
                    Icons.navigation,
                    size: 13,
                    color: Colors.black,
                  ),
                )
              : null,
        ),
        const SizedBox(height: 3),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: color.withValues(alpha: 0.42)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                node.callSign,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (memberStatus case final status?
                  when status != MemberStatus.ok)
                Text(
                  status.label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: status.urgent ? dangerRed : status.color,
                    fontSize: 8,
                    fontWeight: FontWeight.w900,
                  ),
                )
              else if (!node.isSelf)
                Text(
                  node.linkStatus.label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 8,
                    fontWeight: FontWeight.w900,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class WaypointMapMarker extends StatelessWidget {
  const WaypointMapMarker({required this.waypoint, super.key});

  final TacticalWaypoint waypoint;

  @override
  Widget build(BuildContext context) {
    final color = waypoint.priority ? dangerRed : signalAmber;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          height: 24,
          width: 24,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.78),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: color, width: 2),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.28),
                blurRadius: 12,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Icon(waypoint.icon, size: 15, color: color),
        ),
        const SizedBox(height: 3),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.78),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: color.withValues(alpha: 0.5)),
          ),
          child: Text(
            waypoint.code,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }
}

class MapLegend extends StatelessWidget {
  const MapLegend({required this.pttActive, super.key});

  final bool pttActive;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            pttActive ? Icons.record_voice_over : Icons.hearing,
            size: 16,
            color: pttActive ? signalAmber : sand,
          ),
          const SizedBox(width: 6),
          Text(
            pttActive ? 'PTT TX' : 'PTT RX',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

/// Caps a floating card at [maxHeight] and scrolls its content, so on a
/// short map (phone in landscape, large font) its top row with the close
/// button stays on screen.
class _FitAboveSheet extends StatelessWidget {
  const _FitAboveSheet({required this.maxHeight, required this.child});

  final double maxHeight;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight < 0 ? 0 : maxHeight),
      child: SingleChildScrollView(child: child),
    );
  }
}
