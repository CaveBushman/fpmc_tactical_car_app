import 'dart:async';

import 'package:flutter/material.dart';

import 'controllers/offline_maps_controller.dart';
import 'controllers/tactical_controller.dart';
import 'screens/login_screen.dart';
import 'screens/map_page.dart';
import 'screens/messages_page.dart';
import 'screens/systems_page.dart';
import 'screens/team_page.dart';
import 'services/location_service.dart';
import 'services/mesh_packet_repository.dart';
import 'services/meshtastic_ble_service.dart';
import 'theme.dart';
import 'widgets/common_widgets.dart';

class TacticalCarApp extends StatelessWidget {
  const TacticalCarApp({
    this.locationService,
    this.meshPacketRepository,
    this.meshtasticBleService,
    this.offlineMaps,
    super.key,
  });

  final LocationService? locationService;
  final MeshPacketRepository? meshPacketRepository;
  final MeshtasticBleService? meshtasticBleService;
  final OfflineMapsController? offlineMaps;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tactical Mesh',
      debugShowCheckedModeBanner: false,
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
        locationService: locationService,
        meshPacketRepository: meshPacketRepository,
        meshtasticBleService: meshtasticBleService,
        offlineMaps: offlineMaps,
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
    super.key,
  });

  final LocationService? locationService;
  final MeshPacketRepository? meshPacketRepository;
  final MeshtasticBleService? meshtasticBleService;
  final OfflineMapsController? offlineMaps;

  @override
  State<TacticalHomeScreen> createState() => _TacticalHomeScreenState();
}

class _TacticalHomeScreenState extends State<TacticalHomeScreen> {
  late final TacticalController _controller;
  late final OfflineMapsController _offlineMaps;
  late final StreamSubscription<String> _noticeSubscription;
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _controller = TacticalController(
      locationService: widget.locationService,
      meshPacketRepository: widget.meshPacketRepository,
      meshtasticBleService: widget.meshtasticBleService,
    );
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

  @override
  void dispose() {
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
    final pttState = controller.pttState;

    MapPage mapPage({bool showDetailsSheet = true}) => MapPage(
      nodes: nodes,
      waypoints: controller.waypoints,
      pttActive: controller.pttActive,
      locationState: controller.locationState,
      channelLabel: controller.selectedGroup.name,
      tileSource: _offlineMaps.source,
      offlineStore: _offlineMaps.store,
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
      ),
      SystemsPage(
        meshConnected: controller.meshConnected,
        internetVoiceOnline: controller.internetVoiceOnline,
        onVoiceChanged: controller.setInternetVoiceOnline,
        onBleConnect: controller.connectRadio,
        bleState: controller.bleState,
        packetDiagnostics: controller.packetDiagnostics,
        pttState: pttState,
        locationState: controller.locationState,
        onLocationStart: controller.startLocation,
        onLocationSettings: controller.openLocationSettings,
        fontScale: controller.fontScale,
        onFontScaleChanged: controller.setFontScale,
        offlineMaps: _offlineMaps,
        mapCenter: selfNode.latLng,
      ),
    ];

    final screen = MediaQuery.sizeOf(context);
    // Phones: shorter bars and icon-only header so the map keeps the screen.
    final narrow = screen.width < 480;
    final short = screen.height < 800;

    PttBar pttBar({bool compact = false}) => PttBar(
      active: controller.pttActive,
      enabled: controller.internetVoiceOnline,
      compact: compact,
      channel: pttState.channel,
      userName: selfNode.callSign,
      encrypted: pttState.encrypted,
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
            voiceOnline: controller.internetVoiceOnline,
            pttActive: controller.pttActive,
          ),
          SizedBox(width: narrow ? 2 : 8),
          UserSessionChip(
            session: session,
            onLogout: _confirmLogout,
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
                                  (constraints.maxWidth.clamp(320, 430) * 0.95)
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
