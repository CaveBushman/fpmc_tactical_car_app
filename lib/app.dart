import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';

import 'controllers/offline_maps_controller.dart';
import 'controllers/tactical_controller.dart';
import 'models/navigation.dart';
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
import 'widgets/rendezvous_banner.dart';
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

  /// Cross-tab requests: a member to write to, a point to show on the map.
  String? _composeTo;
  LatLng? _mapFocusRequest;

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
    _controller.addListener(_syncSystemBars);
    _syncSystemBars();
    _controller.addListener(_alertOnSos);
    _controller.addListener(_alertOnDanger);
    _controller.addListener(_alertOnStatus);
    _controller.addListener(_alertOnLostContact);
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

  bool? _systemBarsHidden;

  /// Immersive (sticky) mode while the setting is on: the bars slide in
  /// after a swipe from the edge and hide again on their own.
  void _syncSystemBars({bool force = false}) {
    final hide = _controller.hideSystemBars;
    if (!force && hide == _systemBarsHidden) {
      return;
    }
    _systemBarsHidden = hide;
    unawaited(
      SystemChrome.setEnabledSystemUIMode(
        hide ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final resumed = state == AppLifecycleState.resumed;
    _controller.setAppInForeground(resumed);
    if (resumed) {
      // Android may show the bars again after another app was in front.
      _syncSystemBars(force: true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_syncNightMode);
    _controller.removeListener(_syncSystemBars);
    _controller.removeListener(_alertOnSos);
    _controller.removeListener(_alertOnDanger);
    _controller.removeListener(_alertOnStatus);
    _controller.removeListener(_alertOnLostContact);
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
      return LoginScreen(
        onLogin: controller.login,
        lastUserName: controller.lastUserName,
      );
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
      navTarget: controller.navTarget,
      peerTrails: controller.peerTrails,
      onClearOldWaypoints: controller.clearOldReceivedWaypoints,
      focusRequest: _mapFocusRequest,
      onSetRendezvous: (waypoint, at) =>
          unawaited(controller.setRendezvous(waypoint, at)),
      onFocusConsumed: () => setState(() => _mapFocusRequest = null),
      baseCode: controller.baseWaypoint?.code,
      speedKmh: controller.travelSpeedKmh,
      courseDeg: controller.courseDeg,
      statusOf: (callSign) => controller.statusOf(callSign)?.status,
      headingUp: controller.mapHeadingUp,
      onHeadingUpChanged: controller.setMapHeadingUp,
      onNavigate: controller.navigateTo,
      onClearNavTarget: controller.clearNavTarget,
      onShareWaypoint: controller.shareWaypoint,
      onDeleteWaypoint: controller.removeWaypoint,
      onCreateWaypoint: (draft) {
        final editing = draft.editing;
        final waypoint = editing == null
            ? controller.addWaypoint(
                type: draft.type,
                latitude: draft.latitude,
                longitude: draft.longitude,
                code: draft.code,
                note: draft.note,
              )
            : controller.updateWaypoint(
                editing,
                type: draft.type,
                note: draft.note,
              );
        if (draft.isBase) {
          controller.setBase(waypoint);
        } else if (controller.baseWaypoint?.code == waypoint.code) {
          controller.setBase(null);
        }
        if (draft.share) {
          unawaited(controller.shareWaypoint(waypoint));
        }
      },
    );

    final detailPages = [
      TeamPage(
        nodes: nodes,
        onCheckIn: controller.sendCheckIn,
        onNavigate: (node) {
          controller.navigateTo(NavTarget.node(node.nodeNum));
          _selectTab(0);
        },
        onMessage: (node) {
          setState(() => _composeTo = node.callSign);
          _selectTab(messagesTabIndex);
        },
        statusOf: controller.statusOf,
        ownStatus: controller.ownStatus,
        onOwnStatus: (status) => unawaited(controller.setOwnStatus(status)),
      ),
      MessagesPage(
        messages: controller.messages,
        groups: controller.allowedGroups,
        nodes: controller.peers,
        selfNode: selfNode,
        waypoints: controller.waypoints,
        selectedGroupIndex: controller.selectedGroupIndex,
        unreadIn: controller.unreadIn,
        quickMessages: controller.quickMessages,
        directTo: _composeTo,
        onDirectConsumed: () => setState(() => _composeTo = null),
        onShowOnMap: (point) {
          setState(() => _mapFocusRequest = point);
          _selectTab(0);
        },
        onNavigateToSender: (callSign) {
          if (controller.navigateToMember(callSign)) {
            _selectTab(0);
          }
        },
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
        nightModeAuto: controller.nightModeAuto,
        onNightModeAutoChanged: controller.setNightModeAuto,
        mgrsGrid: controller.mgrsGrid,
        onMgrsGridChanged: controller.setMgrsGrid,
        batterySaver: controller.batterySaver,
        onBatterySaverChanged: controller.setBatterySaver,
        dangerAlerts: controller.dangerAlerts,
        onDangerAlertsChanged: controller.setDangerAlerts,
        lostContactAlerts: controller.lostContactAlerts,
        onLostContactAlertsChanged: controller.setLostContactAlerts,
        hideSystemBars: controller.hideSystemBars,
        onHideSystemBarsChanged: controller.setHideSystemBars,
        quickMessages: controller.quickMessages,
        onQuickMessagesChanged: controller.setQuickMessages,
        sharePositionToMesh: controller.sharePositionToMesh,
        onSharePositionToMeshChanged: controller.setSharePositionToMesh,
        trackPoints: controller.track.length,
        missionEvents: controller.missionEvents,
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
              MemberStatusBanners(
                alerts: controller.urgentStatuses,
                onAcknowledge: controller.acknowledgeStatus,
                onNavigate: controller.navigateToMember,
              ),
              RendezvousBanner(
                meeting: controller.rendezvous,
                isOwn:
                    controller.rendezvous?.setBy ==
                    controller.selfNode.callSign,
                solution: controller.rendezvousSolution,
                speedKmh: controller.travelSpeedKmh,
                onNavigate: () => controller.navigateTo(
                  NavTarget.waypoint(controller.rendezvous!.code),
                ),
                onClose: () {
                  if (controller.rendezvous?.setBy ==
                      controller.selfNode.callSign) {
                    unawaited(controller.cancelRendezvous());
                  } else {
                    controller.dismissRendezvous();
                  }
                },
              ),
              LostContactBanners(
                contacts: controller.lostContacts,
                onAcknowledge: controller.acknowledgeLostContact,
                onNavigate: (contact) =>
                    controller.navigateTo(NavTarget.node(contact.nodeNum)),
              ),
              DangerBanners(
                warnings: controller.dangerWarnings,
                onDismiss: controller.dismissDanger,
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
                                  unreadMessages: controller.unreadTotal,
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
              destinations: tacticalDestinations(
                unreadMessages: controller.unreadTotal,
              ),
            ),
          );
        },
      ),
    );
  }

  void _selectTab(int index) {
    setState(() => _selectedIndex = index);
    _controller.setMessagesVisible(index == messagesTabIndex);
  }

  /// Panic wipe behind a 3 s hold: no backend call, no further questions.
  Future<void> _emergencyWipe() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        // Scrolls when the keyboard leaves little room (phone in landscape).
        scrollable: true,
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
    _selectTab(0);
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

  final Set<String> _seenLost = {};

  /// Vibrates once whenever a teammate goes silent.
  void _alertOnLostContact() {
    var fresh = false;
    for (final contact in _controller.lostContacts) {
      if (_seenLost.add(
        '${contact.nodeNum}@${contact.lastSeenAt.microsecondsSinceEpoch}',
      )) {
        fresh = true;
      }
    }
    if (fresh) {
      unawaited(HapticFeedback.vibrate());
    }
  }

  final Set<String> _seenStatus = {};

  /// Vibrates once for every new urgent status from a teammate.
  void _alertOnStatus() {
    var fresh = false;
    for (final alert in _controller.urgentStatuses) {
      if (_seenStatus.add(
        '${alert.callSign}@${alert.report.at.microsecondsSinceEpoch}',
      )) {
        fresh = true;
      }
    }
    if (fresh) {
      unawaited(HapticFeedback.vibrate());
    }
  }

  final Set<String> _seenDanger = {};

  /// Vibrates once per approach to a DANGER point.
  void _alertOnDanger() {
    var fresh = false;
    for (final warning in _controller.dangerWarnings) {
      if (_seenDanger.add(
        '${warning.waypoint.code}@${warning.enteredAt.microsecondsSinceEpoch}',
      )) {
        fresh = true;
      }
    }
    if (fresh) {
      unawaited(HapticFeedback.heavyImpact());
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
        // Scrolls when the keyboard leaves little room (phone in landscape).
        scrollable: true,
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
      _selectTab(0);
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

const messagesTabIndex = 2;

List<NavigationDestination> tacticalDestinations({int unreadMessages = 0}) => [
  const NavigationDestination(
    icon: Icon(Icons.map_outlined),
    selectedIcon: Icon(Icons.map),
    label: 'Mapa',
  ),
  const NavigationDestination(
    icon: Icon(Icons.groups_2_outlined),
    selectedIcon: Icon(Icons.groups_2),
    label: 'Tým',
  ),
  NavigationDestination(
    icon: UnreadBadge(
      count: unreadMessages,
      child: const Icon(Icons.chat_bubble_outline),
    ),
    selectedIcon: UnreadBadge(
      count: unreadMessages,
      child: const Icon(Icons.chat_bubble),
    ),
    label: 'Zprávy',
  ),
  const NavigationDestination(
    icon: Icon(Icons.settings_outlined),
    selectedIcon: Icon(Icons.settings),
    label: 'Systém',
  ),
];
