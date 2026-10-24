import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'controllers/offline_maps_controller.dart';
import 'controllers/tactical_controller.dart';
import 'models/track.dart';
import 'screens/car_mode_screen.dart';
import 'screens/login_screen.dart';
import 'screens/map_page.dart';
import 'screens/messages_page.dart';
import 'screens/systems_page.dart';
import 'screens/team_page.dart';
import 'services/backend_client.dart';
import 'services/location_service.dart';
import 'services/ptt/voice_transport.dart';
import 'services/mesh_packet_repository.dart';
import 'services/mesh_radio.dart';
import 'services/offline_tiles/tile_math.dart';
import 'theme.dart';
import 'widgets/common_widgets.dart';
import 'widgets/sos_widgets.dart';

/// Red, dimmed rendering that keeps night vision: luminance goes to the red
/// channel only, at reduced intensity. Applied over the whole navigator,
/// map tiles and dialogs included.
const nightModeFilter = ColorFilter.matrix([
  0.30, 0.50, 0.08, 0, 0, //
  0.02, 0.04, 0.01, 0, 0, //
  0, 0, 0, 0, 0, //
  0, 0, 0, 1, 0, //
]);

class TacticalCarApp extends StatefulWidget {
  const TacticalCarApp({
    this.locationService,
    this.meshPacketRepository,
    this.meshtasticBleService,
    this.offlineMaps,
    this.backend,
    this.voiceTransportFactory,
    super.key,
  });

  final LocationService? locationService;
  final MeshPacketRepository? meshPacketRepository;
  final MeshRadio? meshtasticBleService;
  final OfflineMapsController? offlineMaps;

  /// Defaults to BACKEND_URL; null there means demo accounts and PTT.
  final BackendClient? backend;
  final VoiceTransport Function()? voiceTransportFactory;

  @override
  State<TacticalCarApp> createState() => _TacticalCarAppState();
}

class _TacticalCarAppState extends State<TacticalCarApp> {
  final ValueNotifier<bool> _nightMode = ValueNotifier(false);

  @override
  void dispose() {
    _nightMode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tactical Mesh',
      debugShowCheckedModeBanner: false,
      builder: (context, child) => ValueListenableBuilder<bool>(
        valueListenable: _nightMode,
        builder: (context, night, _) => night
            ? ColorFiltered(
                key: const ValueKey('night-mode'),
                colorFilter: nightModeFilter,
                child: child,
              )
            : child ?? const SizedBox.shrink(),
      ),
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: fieldBlack,
        colorScheme: ColorScheme.fromSeed(
          seedColor: rangerGreen,
          brightness: Brightness.dark,
          primary: rangerGreen,
          secondary: signalAmber,
          surface: panelGreen,
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          backgroundColor: fieldBlack,
          foregroundColor: Colors.white,
          centerTitle: false,
          elevation: 0,
        ),
        cardTheme: CardThemeData(
          color: panelGreen,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
          ),
        ),
      ),
      home: TacticalHomeScreen(
        locationService: widget.locationService,
        meshPacketRepository: widget.meshPacketRepository,
        meshtasticBleService: widget.meshtasticBleService,
        offlineMaps: widget.offlineMaps,
        backend: widget.backend,
        voiceTransportFactory: widget.voiceTransportFactory,
        nightMode: _nightMode,
      ),
    );
  }
}

class TacticalHomeScreen extends StatefulWidget {
  const TacticalHomeScreen({
    this.locationService,
    this.meshPacketRepository,
    this.meshtasticBleService,
    this.offlineMaps,
    this.backend,
    this.voiceTransportFactory,
    this.nightMode,
    super.key,
  });

  final LocationService? locationService;
  final MeshPacketRepository? meshPacketRepository;
  final MeshRadio? meshtasticBleService;
  final OfflineMapsController? offlineMaps;

  /// Defaults to BACKEND_URL; null there means demo accounts and PTT.
  final BackendClient? backend;
  final VoiceTransport Function()? voiceTransportFactory;

  /// App-level switch for the red night filter, driven by the setting.
  final ValueNotifier<bool>? nightMode;

  @override
  State<TacticalHomeScreen> createState() => _TacticalHomeScreenState();
}

class _TacticalHomeScreenState extends State<TacticalHomeScreen>
    with WidgetsBindingObserver {
  late final TacticalController _controller;
  late final OfflineMapsController _offlineMaps;

  /// Last area shown on the map; offered for offline download.
  TileBounds? _visibleMapBounds;
  late final StreamSubscription<String> _noticeSubscription;
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = TacticalController(
      locationService: widget.locationService,
      meshPacketRepository: widget.meshPacketRepository,
      meshtasticBleService: widget.meshtasticBleService,
      backend:
          widget.backend ??
          (backendUrlFromEnvironment.isEmpty
              ? null
              : BackendClient(baseUrl: backendUrlFromEnvironment)),
      voiceTransportFactory: widget.voiceTransportFactory,
    );
    _controller.addListener(_syncNightMode);
    _controller.addListener(_alertOnSos);
    _offlineMaps = widget.offlineMaps ?? OfflineMapsController();
    unawaited(_offlineMaps.init());
    _noticeSubscription = _controller.notices.listen((message) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: dangerRed),
      );
    });
  }

  void _syncNightMode() {
    widget.nightMode?.value = _controller.nightMode;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _controller.setAppInForeground(state == AppLifecycleState.resumed);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_syncNightMode);
    _controller.removeListener(_alertOnSos);
    unawaited(_noticeSubscription.cancel());
    _controller.dispose();
    _offlineMaps.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) => _buildForSession(context),
    );
  }

  Widget _buildForSession(BuildContext context) {
    final controller = _controller;
    final session = controller.session;
    if (session == null) {
      return LoginScreen(onLogin: controller.login);
    }

    final nodes = controller.nodes;
    final selfNode = controller.selfNode;
    final ptt = controller.ptt;

    MapPage mapPage({bool showDetailsSheet = true}) => MapPage(
      nodes: nodes,
      waypoints: controller.waypoints,
      pttActive: controller.pttActive,
      locationState: controller.locationState,
      channelLabel: controller.selectedGroup.name,
      tileSource: _offlineMaps.source,
      offlineStore: _offlineMaps.store,
      onVisibleBoundsChanged: (bounds) => _visibleMapBounds = bounds,
      track: [for (final point in controller.track) point.latLng],
      showGrid: controller.mgrsGrid,
      onSharePoint: (point) => unawaited(controller.sharePoint(point)),
      showDetailsSheet: showDetailsSheet,
      onShareWaypoint: controller.shareWaypoint,
      onDeleteWaypoint: controller.removeWaypoint,
      onCreateWaypoint: (draft) {
        final waypoint = controller.addWaypoint(
          type: draft.type,
          latitude: draft.latitude,
          longitude: draft.longitude,
          code: draft.code,
          note: draft.note,
        );
        if (draft.share) {
          unawaited(controller.shareWaypoint(waypoint));
        }
      },
    );

    final detailPages = [
      TeamPage(nodes: nodes, onCheckIn: controller.sendCheckIn),
      MessagesPage(
        messages: controller.messages,
        groups: controller.allowedGroups,
        nodes: controller.peers,
        selfNode: selfNode,
        waypoints: controller.waypoints,
        selectedGroupIndex: controller.selectedGroupIndex,
        onGroupSelected: controller.selectGroup,
        onSend: controller.sendMeshText,
        onRetry: controller.retryMessage,
        onSos: _toggleSos,
      ),
      SystemsPage(
        meshConnected: controller.meshConnected,
        ptt: ptt,
        onPttReconnect: controller.reconnectPtt,
        nightMode: controller.nightMode,
        onNightModeChanged: controller.setNightMode,
        mgrsGrid: controller.mgrsGrid,
        onMgrsGridChanged: controller.setMgrsGrid,
        batterySaver: controller.batterySaver,
        onBatterySaverChanged: controller.setBatterySaver,
        sharePositionToMesh: controller.sharePositionToMesh,
        onSharePositionToMeshChanged: controller.setSharePositionToMesh,
        trackPoints: controller.track.length,
        trackLengthKm: trackLengthKm(controller.track),
        onExportMission: controller.exportMission,
        onClearTrack: controller.clearTrack,
        onCopyPacketRecording: controller.exportPacketRecording,
        radioChannels: controller.radioChannels,
        channelWarnings: controller.channelWarnings,
        volumeKeyPtt: controller.volumeKeyPtt,
        onVolumeKeyPttChanged: controller.setVolumeKeyPtt,
        onBleConnect: controller.connectRadio,
        bleState: controller.bleState,
        packetDiagnostics: controller.packetDiagnostics,
        locationState: controller.locationState,
        onLocationStart: controller.startLocation,
        onLocationSettings: controller.openLocationSettings,
        fontScale: controller.fontScale,
        onFontScaleChanged: controller.setFontScale,
        offlineMaps: _offlineMaps,
        mapCenter: selfNode.latLng,
        visibleMapBounds: _visibleMapBounds,
      ),
    ];

    final screen = MediaQuery.sizeOf(context);
    // Phones: shorter bars and icon-only header so the map keeps the screen.
    final narrow = screen.width < 480;
    final short = screen.height < 800;

    PttBar pttBar({bool compact = false}) => PttBar(
      status: ptt.status,
      speaker: ptt.speaker,
      demo: ptt.isDemo,
      compact: compact,
      channel: ptt.channel,
      userName: selfNode.callSign,
      onChanged: controller.setPttActive,
    );

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: short ? 46 : kToolbarHeight,
        titleSpacing: narrow ? 8 : null,
        title: AppBrand(compact: narrow),
        actions: [
          StatusIcons(
            meshConnected: controller.meshConnected,
            voiceOnline: controller.voiceOnline,
            pttActive: controller.pttActive,
            dense: narrow,
          ),
          IconButton(
            tooltip: 'Režim auta',
            visualDensity: VisualDensity.compact,
            padding: narrow ? EdgeInsets.zero : null,
            constraints: narrow
                ? const BoxConstraints(minWidth: 30, minHeight: 40)
                : null,
            iconSize: narrow ? 22 : null,
            onPressed: _openCarMode,
            icon: const Icon(Icons.directions_car_filled_outlined),
          ),
          UserSessionChip(
            session: session,
            onLogout: _confirmLogout,
            onEmergencyWipe: _emergencyWipe,
            compact: narrow,
          ),
          SizedBox(width: narrow ? 4 : 10),
          const TimeReadout(),
          SizedBox(width: narrow ? 8 : 12),
        ],
      ),
      body: SafeArea(
        child: _ScaledTextContent(
          fontScale: controller.fontScale,
          child: Column(
            children: [
              SosBanners(
                ownActive: controller.sosActive,
                alerts: controller.activeSosAlerts,
                onCancelOwn: () => unawaited(controller.stopSos()),
                onAcknowledge: (alert) =>
                    unawaited(controller.acknowledgeSos(alert)),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final landscape =
                        constraints.maxWidth > constraints.maxHeight &&
                        constraints.maxWidth >= 720;
                    if (landscape) {
                      final fullMapMode = _selectedIndex == 0;
                      return Column(
                        children: [
                          Expanded(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                TacticalNavigationRail(
                                  selectedIndex: _selectedIndex,
                                  onDestinationSelected: _selectTab,
                                ),
                                Expanded(
                                  flex: fullMapMode ? 1 : 7,
                                  child: mapPage(showDetailsSheet: fullMapMode),
                                ),
                                if (!fullMapMode)
                                  SizedBox(
                                    width:
                                        (constraints.maxWidth.clamp(320, 430) *
                                                0.95)
                                            .toDouble(),
                                    child: detailPages[_selectedIndex - 1],
                                  ),
                              ],
                            ),
                          ),
                          pttBar(compact: true),
                        ],
                      );
                    }

                    return Column(
                      children: [
                        Expanded(
                          child: _selectedIndex == 0
                              ? mapPage()
                              : detailPages[_selectedIndex - 1],
                        ),
                        pttBar(compact: short),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: OrientationBuilder(
        builder: (context, orientation) {
          final size = MediaQuery.sizeOf(context);
          final landscape = size.width > size.height && size.width >= 720;
          if (landscape) {
            return const SizedBox.shrink();
          }
          return _ScaledTextContent(
            fontScale: controller.fontScale,
            child: NavigationBar(
              height: short ? 58 : null,
              labelBehavior: short
                  ? NavigationDestinationLabelBehavior.onlyShowSelected
                  : null,
              backgroundColor: const Color(0xFF171B13),
              indicatorColor: rangerGreen.withValues(alpha: 0.85),
              selectedIndex: _selectedIndex,
              onDestinationSelected: _selectTab,
              destinations: tacticalDestinations,
            ),
          );
        },
      ),
    );
  }

  void _selectTab(int index) => setState(() => _selectedIndex = index);

  /// Panic wipe behind a 3 s hold: no backend call, no further questions.
  Future<void> _emergencyWipe() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: panelGreen,
        title: const Text('Nouzově smazat data'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Okamžitě smaže zprávy, pozice, stopu, šifrovací klíč, offline '
              'mapy a nastavení, odpojí T-Beam a odhlásí. Nelze vrátit.',
            ),
            const SizedBox(height: 16),
            HoldToConfirmButton(
              key: const ValueKey('wipe-hold'),
              label: 'DRŽ 3 s PRO SMAZÁNÍ',
              onConfirmed: () => Navigator.of(context).pop(true),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Zrušit'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    setState(() => _selectedIndex = 0);
    await _controller.emergencyWipe();
    try {
      await _offlineMaps.clear();
    } catch (_) {
      // Tiles unavailable on this platform.
    }
  }

  Future<void> _toggleSos() async {
    if (_controller.sosActive) {
      await _controller.stopSos();
    } else if (await confirmSosStart(context)) {
      await _controller.startSos();
    }
  }

  final Set<String> _seenSos = {};

  /// Vibrates once for every new or repeated distress call.
  void _alertOnSos() {
    var fresh = false;
    for (final alert in _controller.activeSosAlerts) {
      if (_seenSos.add(
        '${alert.callSign}@${alert.lastAt.millisecondsSinceEpoch}',
      )) {
        fresh = true;
      }
    }
    if (fresh) {
      unawaited(HapticFeedback.vibrate());
    }
  }

  void _openCarMode() {
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) =>
              CarModeScreen(controller: _controller, offlineMaps: _offlineMaps),
        ),
      ),
    );
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: panelGreen,
        title: const Text('Odhlásit a smazat data?'),
        content: const Text(
          'Zprávy, pozice týmu a šifrovací klíč lokálního úložiště budou '
          'z tohoto zařízení nevratně smazány. T-Beam se odpojí.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Zrušit'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: dangerRed),
            child: const Text('Odhlásit a smazat'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      setState(() => _selectedIndex = 0);
      await _controller.logout();
    }
  }
}

class _ScaledTextContent extends StatelessWidget {
  const _ScaledTextContent({required this.fontScale, required this.child});

  final double fontScale;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(fontScale)),
      child: child,
    );
  }
}

const tacticalDestinations = [
  NavigationDestination(
    icon: Icon(Icons.map_outlined),
    selectedIcon: Icon(Icons.map),
    label: 'Mapa',
  ),
  NavigationDestination(
    icon: Icon(Icons.groups_2_outlined),
    selectedIcon: Icon(Icons.groups_2),
    label: 'Tým',
  ),
  NavigationDestination(
    icon: Icon(Icons.chat_bubble_outline),
    selectedIcon: Icon(Icons.chat_bubble),
    label: 'Zprávy',
  ),
  NavigationDestination(
    icon: Icon(Icons.settings_outlined),
    selectedIcon: Icon(Icons.settings),
    label: 'Systém',
  ),
];
