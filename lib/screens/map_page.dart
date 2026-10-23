import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/mesh_node.dart';
import '../models/navigation.dart';
import '../services/location_service.dart';
import '../theme.dart';
import '../widgets/common_widgets.dart';
import '../widgets/navigation_widgets.dart';
import '../widgets/node_widgets.dart';
import '../widgets/position_widgets.dart';

class MapPage extends StatelessWidget {
  const MapPage({
    required this.nodes,
    required this.waypoints,
    required this.pttActive,
    required this.onShareWaypoint,
    this.locationState = LocationState.idle,
    this.compact = false,
    super.key,
  });

  final List<MeshNode> nodes;
  final List<TacticalWaypoint> waypoints;
  final bool pttActive;
  final ValueChanged<TacticalWaypoint> onShareWaypoint;
  final LocationState locationState;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final self = nodes.firstWhere((node) => node.isSelf);
    final health = NodeHealthSummary.fromNodes(nodes);
    final navSolutions = TacticalNavSolution.fromMission(
      self: self,
      nodes: nodes,
      waypoints: waypoints,
    );
    if (compact) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 8, 12),
        child: Column(
          children: [
            Expanded(
              child: Card(
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: MeshMap(nodes: nodes, waypoints: waypoints),
                    ),
                    Positioned(
                      left: 12,
                      top: 12,
                      child: CoordinatePanel(
                        node: self,
                        locationState: locationState,
                        compact: true,
                      ),
                    ),
                    Positioned(
                      right: 12,
                      bottom: 12,
                      child: MapLegend(pttActive: pttActive),
                    ),
                    if (navSolutions.isNotEmpty)
                      Positioned(
                        right: 12,
                        top: 52,
                        child: NavigationCueBadge(solution: navSolutions.first),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 78,
              child: Row(
                children: [
                  Expanded(
                    child: MetricTile(
                      label: 'OK',
                      value: '${health.ok}',
                      icon: Icons.hub_outlined,
                      compact: true,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: MetricTile(
                      label: 'Kanál',
                      value: 'ALPHA',
                      icon: Icons.radio,
                      compact: true,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: MetricTile(
                      label: 'STALE',
                      value: '${health.stale}',
                      icon: Icons.schedule_outlined,
                      compact: true,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: MetricTile(
                      label: 'LOST',
                      value: '${health.lost}',
                      icon: Icons.signal_wifi_connected_no_internet_4_outlined,
                      compact: true,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 112,
              child: WaypointStrip(
                waypoints: waypoints,
                onShareWaypoint: onShareWaypoint,
                compact: true,
              ),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      children: [
        SizedBox(
          height: 390,
          child: Card(
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                Positioned.fill(
                  child: MeshMap(nodes: nodes, waypoints: waypoints),
                ),
                Positioned(
                  left: 12,
                  top: 12,
                  child: CoordinatePanel(
                    node: self,
                    locationState: locationState,
                  ),
                ),
                Positioned(
                  right: 12,
                  bottom: 12,
                  child: MapLegend(pttActive: pttActive),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        GridView.count(
          crossAxisCount: MediaQuery.sizeOf(context).width > 640 ? 4 : 2,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 2.7,
          children: [
            MetricTile(
              label: 'OK uzly',
              value: '${health.ok}/${nodes.length}',
              icon: Icons.hub_outlined,
            ),
            MetricTile(
              label: 'Stale',
              value: '${health.stale}',
              icon: Icons.schedule_outlined,
            ),
            MetricTile(
              label: 'Lost',
              value: '${health.lost}',
              icon: Icons.signal_wifi_connected_no_internet_4_outlined,
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
        ),
        const SizedBox(height: 10),
        WaypointStrip(waypoints: waypoints, onShareWaypoint: onShareWaypoint),
      ],
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

class MeshMap extends StatefulWidget {
  const MeshMap({required this.nodes, required this.waypoints, super.key});

  final List<MeshNode> nodes;
  final List<TacticalWaypoint> waypoints;

  @override
  State<MeshMap> createState() => _MeshMapState();
}

class _MeshMapState extends State<MeshMap> {
  final MapController _mapController = MapController();
  bool _mapReady = false;
  bool _followSelf = true;
  LatLng? _lastSelfPoint;

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

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
    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: selfPoint,
            initialZoom: 13.4,
            onMapReady: () => _mapReady = true,
            onPositionChanged: (camera, hasGesture) {
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
              urlTemplate: tacticalMapUrlTemplate,
              userAgentPackageName: 'first_pmc_tactical_car_app',
              tileProvider: NetworkTileProvider(
                cachingProvider:
                    BuiltInMapCachingProvider.getOrCreateInstance(),
              ),
              tileBuilder: _tacticalTileBuilder,
            ),
            PolylineLayer(
              polylines: [
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
              markers: [
                for (final waypoint in waypoints)
                  Marker(
                    point: waypoint.latLng,
                    width: 112,
                    height: 62,
                    child: WaypointMapMarker(waypoint: waypoint),
                  ),
                for (final node in nodes)
                  Marker(
                    point: node.latLng,
                    width: 92,
                    height: 58,
                    child: MapNodeMarker(node: node),
                  ),
              ],
            ),
            const RichAttributionWidget(
              attributions: [TextSourceAttribution('OpenStreetMap')],
              alignment: AttributionAlignment.bottomLeft,
            ),
          ],
        ),
        const Positioned.fill(child: TacticalMapGrid()),
        const Positioned(right: 12, top: 12, child: MapCacheBadge()),
        Positioned(
          left: 12,
          bottom: 36,
          child: IconButton.filled(
            tooltip: _followSelf
                ? 'Mapa sleduje vlastní pozici'
                : 'Vycentrovat na vlastní pozici',
            onPressed: _recenter,
            style: IconButton.styleFrom(
              backgroundColor: _followSelf
                  ? rangerGreen
                  : Colors.black.withValues(alpha: 0.76),
              foregroundColor: _followSelf ? Colors.white : sand,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            icon: Icon(
              _followSelf ? Icons.my_location : Icons.location_searching,
            ),
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

class TacticalMapGrid extends StatelessWidget {
  const TacticalMapGrid({super.key});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: TacticalMapGridPainter(),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class TacticalMapGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()..color = Colors.black.withValues(alpha: 0.18);
    canvas.drawRect(Offset.zero & size, bg);

    final gridPaint = Paint()
      ..color = rangerGreen.withValues(alpha: 0.28)
      ..strokeWidth = 1;
    const gridStep = 42.0;
    for (double x = 0; x < size.width; x += gridStep) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y < size.height; y += gridStep) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
  }

  @override
  bool shouldRepaint(covariant TacticalMapGridPainter oldDelegate) => false;
}

class MapNodeMarker extends StatelessWidget {
  const MapNodeMarker({required this.node, super.key});

  final MeshNode node;

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
              ? const Icon(Icons.navigation, size: 13, color: Colors.black)
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
              if (!node.isSelf)
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

class MapCacheBadge extends StatelessWidget {
  const MapCacheBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.76),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: tacticalKhaki.withValues(alpha: 0.45)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.offline_pin_outlined, size: 15, color: sand),
          SizedBox(width: 6),
          Text(
            'MAP CACHE',
            style: TextStyle(
              color: sand,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
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
