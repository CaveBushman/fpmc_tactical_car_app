import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mgrs_dart/mgrs_dart.dart';

import 'models/mesh_node.dart';
import 'models/messaging.dart';
import 'models/navigation.dart';
import 'screens/login_screen.dart';
import 'screens/map_page.dart';
import 'screens/messages_page.dart';
import 'screens/systems_page.dart';
import 'screens/team_page.dart';
import 'services/auth_service.dart';
import 'services/encrypted_ptt_service.dart';
import 'services/location_service.dart';
import 'services/mesh_packet_repository.dart';
import 'services/meshtastic_ble_service.dart';
import 'services/meshtastic_message_encoder.dart';
import 'services/meshtastic_packet_decoder.dart';
import 'services/ptt_access_service.dart';
import 'services/tactical_state_store.dart';
import 'theme.dart';
import 'widgets/common_widgets.dart';
import 'widgets/node_widgets.dart';

class TacticalCarApp extends StatelessWidget {
  const TacticalCarApp({
    this.locationService,
    this.meshPacketRepository,
    this.meshtasticBleService,
    super.key,
  });

  final LocationService? locationService;
  final MeshPacketRepository? meshPacketRepository;
  final MeshtasticBleService? meshtasticBleService;

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
      ),
    );
  }
}

class TacticalHomeScreen extends StatefulWidget {
  const TacticalHomeScreen({
    this.locationService,
    this.meshPacketRepository,
    this.meshtasticBleService,
    super.key,
  });

  final LocationService? locationService;
  final MeshPacketRepository? meshPacketRepository;
  final MeshtasticBleService? meshtasticBleService;

  @override
  State<TacticalHomeScreen> createState() => _TacticalHomeScreenState();
}

class _TacticalHomeScreenState extends State<TacticalHomeScreen> {
  late final Timer _clockTimer;
  late final AuthService _authService;
  late final PttAccessService _pttAccessService;
  late final MeshtasticBleService _meshtasticBleService;
  late final MeshtasticMessageEncoder _messageEncoder;
  late final MeshPacketRepository _meshPacketRepository;
  late final EncryptedPttService _pttService;
  late final TacticalStateStore _stateStore;
  late final LocationService _locationService;
  StreamSubscription<LocationState>? _locationStateSubscription;
  StreamSubscription<LocationFix>? _locationFixSubscription;
  LocationState _locationState = LocationState.idle;
  DateTime? _lastLocationPersistAt;
  final math.Random _packetIdRandom = math.Random.secure();
  StreamSubscription<MeshtasticBleState>? _bleStateSubscription;
  StreamSubscription<MeshtasticBlePacket>? _blePacketSubscription;
  StreamSubscription<MeshPacketDiagnostics>? _packetDiagnosticsSubscription;
  StreamSubscription<List<DecodedMeshEvent>>? _meshEventsSubscription;
  StreamSubscription<EncryptedPttState>? _pttStateSubscription;
  DateTime _now = DateTime.now();
  int _selectedIndex = 0;
  bool _pttActive = false;
  bool _internetVoiceOnline = true;
  bool _meshConnected = false;
  AuthSession? _session;
  int _selectedGroupIndex = 0;
  double _fontScale = 1.0;
  MeshtasticBleState _bleState = MeshtasticBleState.idle;
  MeshPacketDiagnostics _packetDiagnostics = MeshPacketDiagnostics.empty;
  EncryptedPttState _pttState = const EncryptedPttState(
    status: EncryptedPttStatus.ready,
    channel: 'ALPHA',
    encrypted: true,
  );

  final List<MeshNode> _nodes = MeshNode.demoNodes(DateTime.now());
  final List<MeshMessage> _messages = [...MeshMessage.demoMessages];
  final List<CommunicationGroup> _groups = CommunicationGroup.demoGroups;
  final List<TacticalWaypoint> _waypoints = TacticalWaypoint.demoWaypoints;

  @override
  void initState() {
    super.initState();
    _authService = AuthService();
    _pttAccessService = const PttAccessService();
    _meshtasticBleService =
        widget.meshtasticBleService ?? MeshtasticBleService();
    _messageEncoder = const MeshtasticMessageEncoder();
    _meshPacketRepository =
        widget.meshPacketRepository ?? MeshPacketRepository();
    _pttService = EncryptedPttService(channel: 'ALPHA');
    _stateStore = const TacticalStateStore();
    _locationService = widget.locationService ?? GeolocatorLocationService();
    _locationStateSubscription = _locationService.stateStream.listen((state) {
      if (!mounted) {
        return;
      }
      setState(() => _locationState = state);
    });
    _locationFixSubscription = _locationService.fixes.listen(_applySelfFix);
    _bleStateSubscription = _meshtasticBleService.stateStream.listen((state) {
      if (!mounted) {
        return;
      }
      setState(() {
        _bleState = state;
        _meshConnected = state.status == MeshtasticBleStatus.connected;
      });
    });
    _pttStateSubscription = _pttService.stateStream.listen((state) {
      if (!mounted) {
        return;
      }
      setState(() => _pttState = state);
    });
    _blePacketSubscription = _meshtasticBleService.packets.listen(
      _meshPacketRepository.ingest,
    );
    _packetDiagnosticsSubscription = _meshPacketRepository.diagnosticsStream
        .listen((diagnostics) {
          if (!mounted) {
            return;
          }
          setState(() => _packetDiagnostics = diagnostics);
        });
    _meshEventsSubscription = _meshPacketRepository.eventsStream.listen(
      _applyDecodedMeshEvents,
    );
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _clockTimer.cancel();
    unawaited(_bleStateSubscription?.cancel());
    unawaited(_blePacketSubscription?.cancel());
    unawaited(_packetDiagnosticsSubscription?.cancel());
    unawaited(_meshEventsSubscription?.cancel());
    unawaited(_pttStateSubscription?.cancel());
    unawaited(_locationStateSubscription?.cancel());
    unawaited(_locationFixSubscription?.cancel());
    unawaited(_locationService.dispose());
    unawaited(_meshtasticBleService.dispose());
    unawaited(_meshPacketRepository.dispose());
    unawaited(_pttService.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    if (session == null) {
      return LoginScreen(onLogin: _login);
    }

    final allowedGroups = _groups
        .where((group) => session.allowedGroupIds.contains(group.id))
        .toList();
    if (_selectedGroupIndex >= allowedGroups.length) {
      _selectedGroupIndex = 0;
    }

    final portraitPages = [
      MapPage(
        nodes: _nodes,
        waypoints: _waypoints,
        pttActive: _pttActive,
        locationState: _locationState,
        onShareWaypoint: (waypoint) => _shareWaypoint(waypoint, allowedGroups),
      ),
      TeamPage(
        nodes: _nodes,
        onCheckIn: (node) => _sendCheckIn(node, allowedGroups),
      ),
      MessagesPage(
        messages: _messages,
        groups: allowedGroups,
        nodes: _nodes.where((node) => !node.isSelf).toList(),
        selfNode: _selfNode,
        waypoints: _waypoints,
        selectedGroupIndex: _selectedGroupIndex,
        onGroupSelected: (index) => _selectGroup(index, allowedGroups),
        onSend: (draft) => _sendMeshText(draft, allowedGroups),
        onRetry: _retryMessage,
      ),
      SystemsPage(
        meshConnected: _meshConnected,
        internetVoiceOnline: _internetVoiceOnline,
        onVoiceChanged: (value) => setState(() => _internetVoiceOnline = value),
        onBleConnect: _meshtasticBleService.startAutoConnect,
        bleState: _bleState,
        packetDiagnostics: _packetDiagnostics,
        pttState: _pttState,
        locationState: _locationState,
        onLocationStart: _locationService.start,
        onLocationSettings: _locationService.openSettings,
        fontScale: _fontScale,
        onFontScaleChanged: (value) => setState(() => _fontScale = value),
      ),
    ];

    final landscapePages = [
      const SizedBox.shrink(),
      TeamPage(
        nodes: _nodes,
        onCheckIn: (node) => _sendCheckIn(node, allowedGroups),
      ),
      MessagesPage(
        messages: _messages,
        groups: allowedGroups,
        nodes: _nodes.where((node) => !node.isSelf).toList(),
        selfNode: _selfNode,
        waypoints: _waypoints,
        selectedGroupIndex: _selectedGroupIndex,
        onGroupSelected: (index) => _selectGroup(index, allowedGroups),
        onSend: (draft) => _sendMeshText(draft, allowedGroups),
        onRetry: _retryMessage,
      ),
      SystemsPage(
        meshConnected: _meshConnected,
        internetVoiceOnline: _internetVoiceOnline,
        onVoiceChanged: (value) => setState(() => _internetVoiceOnline = value),
        onBleConnect: _meshtasticBleService.startAutoConnect,
        bleState: _bleState,
        packetDiagnostics: _packetDiagnostics,
        pttState: _pttState,
        locationState: _locationState,
        onLocationStart: _locationService.start,
        onLocationSettings: _locationService.openSettings,
        fontScale: _fontScale,
        onFontScaleChanged: (value) => setState(() => _fontScale = value),
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const AppBrand(),
        actions: [
          UserSessionChip(session: session, onLogout: _logout),
          const SizedBox(width: 10),
          TimeReadout(now: _now),
          const SizedBox(width: 12),
        ],
      ),
      body: SafeArea(
        child: _ScaledTextContent(
          fontScale: _fontScale,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final landscape =
                  constraints.maxWidth > constraints.maxHeight &&
                  constraints.maxWidth >= 720;
              if (landscape) {
                final fullMapMode = _selectedIndex == 0;
                return Column(
                  children: [
                    StatusStrip(
                      meshConnected: _meshConnected,
                      voiceOnline: _internetVoiceOnline,
                      pttActive: _pttActive,
                    ),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TacticalNavigationRail(
                            selectedIndex: _selectedIndex,
                            onDestinationSelected: (index) =>
                                setState(() => _selectedIndex = index),
                          ),
                          Expanded(
                            flex: fullMapMode ? 1 : 7,
                            child: MapPage(
                              nodes: _nodes,
                              waypoints: _waypoints,
                              pttActive: _pttActive,
                              locationState: _locationState,
                              compact: true,
                              onShareWaypoint: (waypoint) =>
                                  _shareWaypoint(waypoint, allowedGroups),
                            ),
                          ),
                          if (!fullMapMode)
                            SizedBox(
                              width:
                                  (constraints.maxWidth.clamp(320, 430) * 0.95)
                                      .toDouble(),
                              child: landscapePages[_selectedIndex],
                            ),
                        ],
                      ),
                    ),
                    PttBar(
                      active: _pttActive,
                      enabled: _internetVoiceOnline,
                      compact: true,
                      channel: _pttState.channel,
                      userName: _selfNode.callSign,
                      encrypted: _pttState.encrypted,
                      onChanged: _setPttActive,
                    ),
                  ],
                );
              }

              return Column(
                children: [
                  StatusStrip(
                    meshConnected: _meshConnected,
                    voiceOnline: _internetVoiceOnline,
                    pttActive: _pttActive,
                  ),
                  Expanded(child: portraitPages[_selectedIndex]),
                  PttBar(
                    active: _pttActive,
                    enabled: _internetVoiceOnline,
                    channel: _pttState.channel,
                    userName: _selfNode.callSign,
                    encrypted: _pttState.encrypted,
                    onChanged: _setPttActive,
                  ),
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
            fontScale: _fontScale,
            child: NavigationBar(
              backgroundColor: const Color(0xFF171B13),
              indicatorColor: rangerGreen.withValues(alpha: 0.85),
              selectedIndex: _selectedIndex,
              onDestinationSelected: (index) =>
                  setState(() => _selectedIndex = index),
              destinations: tacticalDestinations,
            ),
          );
        },
      ),
    );
  }

  MeshNode get _selfNode => _nodes.firstWhere((node) => node.isSelf);

  Future<String?> _login(String userName, String password) async {
    final result = await _authService.login(
      userName: userName,
      password: password,
    );
    if (!result.ok) {
      return result.errorMessage;
    }
    setState(() {
      _session = result.session;
      _selectedGroupIndex = 0;
    });
    unawaited(_locationService.start());
    unawaited(_restorePersistedState(result.session!.userName));
    _syncPttChannelForGroup(
      result.session!,
      _groups.firstWhere(
        (group) => group.id == result.session!.allowedGroupIds.first,
      ),
    );
    return null;
  }

  Future<void> _logout() async {
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
    if (confirmed != true || !mounted) {
      return;
    }

    // Drop the session first so no in-flight persist can rewrite the store.
    setState(() {
      _session = null;
      _selectedGroupIndex = 0;
    });
    await _authService.logout();
    await _locationService.stop();
    try {
      await _meshtasticBleService.disconnect();
    } catch (_) {
      // Not connected or plugin unavailable; nothing to tear down.
    }
    try {
      await _stateStore.clear();
    } catch (_) {
      // Storage unavailable; in-memory state is still reset below.
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _nodes
        ..clear()
        ..addAll(MeshNode.demoNodes(DateTime.now()));
      _messages
        ..clear()
        ..addAll(MeshMessage.demoMessages);
    });
  }

  void _setPttActive(bool value) {
    if (value) {
      _pttService.beginTransmit();
    } else {
      _pttService.endTransmit();
    }
    setState(() => _pttActive = value);
  }

  void _selectGroup(int index, List<CommunicationGroup> groups) {
    final session = _session;
    if (session == null) {
      return;
    }
    setState(() => _selectedGroupIndex = index);
    _syncPttChannelForGroup(session, groups[index]);
  }

  void _syncPttChannelForGroup(AuthSession session, CommunicationGroup group) {
    final access = _pttAccessService.authorize(
      session: session,
      groupId: group.id,
    );
    _pttService.switchChannel(
      channel: access.channel,
      keyBytes: access.keyBytes,
    );
  }

  void _applySelfFix(LocationFix fix) {
    if (!mounted) {
      return;
    }
    final selfIndex = _nodes.indexWhere((node) => node.isSelf);
    if (selfIndex == -1) {
      return;
    }
    setState(() {
      final self = _nodes[selfIndex].copyWith(
        latitude: fix.latitude,
        longitude: fix.longitude,
        altitudeM: fix.altitudeM.round(),
        mgrs: _mgrsLabel(fix.latitude, fix.longitude),
        lastSeenAt: fix.timestamp,
      );
      _nodes[selfIndex] = self;
      for (var i = 0; i < _nodes.length; i++) {
        final node = _nodes[i];
        if (node.isSelf) {
          continue;
        }
        _nodes[i] = node.copyWith(
          distanceKm: _distanceKm(
            self.latitude,
            self.longitude,
            node.latitude,
            node.longitude,
          ),
          bearingDeg: _bearingDeg(
            self.latitude,
            self.longitude,
            node.latitude,
            node.longitude,
          ),
        );
      }
    });

    // GPS can fire every few metres; persist the last known position at most
    // every 30 s so a restart still opens on a recent fix.
    final now = DateTime.now();
    final lastPersist = _lastLocationPersistAt;
    if (lastPersist == null ||
        now.difference(lastPersist) > const Duration(seconds: 30)) {
      _lastLocationPersistAt = now;
      unawaited(_persistState());
    }
  }

  void _applyDecodedMeshEvents(List<DecodedMeshEvent> events) {
    if (!mounted) {
      return;
    }

    var changed = false;
    setState(() {
      for (final event in events) {
        switch (event.type) {
          case DecodedMeshEventType.myInfo:
            changed = _adoptRadioNodeNum(event.nodeNum) || changed;
          case DecodedMeshEventType.configComplete:
            break;
          case DecodedMeshEventType.nodeInfo:
          case DecodedMeshEventType.position:
            changed = _upsertMeshNode(event) || changed;
          case DecodedMeshEventType.textMessage:
            changed = _appendIncomingMeshMessage(event) || changed;
          case DecodedMeshEventType.routing:
            changed = _applyRoutingResult(event) || changed;
          case DecodedMeshEventType.encrypted:
          case DecodedMeshEventType.unknown:
            break;
        }
      }
    });
    if (changed) {
      unawaited(_persistState());
    }
  }

  /// MyNodeInfo tells us which node number the connected T-Beam uses; the
  /// self node must carry it so our own echoes are not shown as a peer.
  bool _adoptRadioNodeNum(int? nodeNum) {
    if (nodeNum == null) {
      return false;
    }
    final selfIndex = _nodes.indexWhere((node) => node.isSelf);
    if (selfIndex == -1 || _nodes[selfIndex].nodeNum == nodeNum) {
      return false;
    }
    final self = _nodes[selfIndex].copyWith(nodeNum: nodeNum);
    _nodes.removeWhere((node) => node.isSelf || node.nodeNum == nodeNum);
    _nodes.insert(0, self);
    return true;
  }

  bool _upsertMeshNode(DecodedMeshEvent event) {
    final nodeNum = event.nodeNum ?? event.from;
    if (nodeNum == null) {
      return false;
    }
    if (nodeNum == _selfNode.nodeNum) {
      // Our own NodeInfo from the radio carries the configured callsign;
      // position stays driven by the phone GPS.
      final name = _eventCallSign(event);
      if (name == null || name == _selfNode.callSign) {
        return false;
      }
      final selfIndex = _nodes.indexWhere((node) => node.isSelf);
      _nodes[selfIndex] = _selfNode.copyWith(callSign: name);
      return true;
    }

    final existingIndex = _nodes.indexWhere((node) => node.nodeNum == nodeNum);
    final existing = existingIndex == -1 ? null : _nodes[existingIndex];
    final latitude = event.latitude ?? existing?.latitude;
    final longitude = event.longitude ?? existing?.longitude;
    if (latitude == null || longitude == null) {
      return false;
    }

    final callSign =
        _eventCallSign(event) ?? existing?.callSign ?? _nodeHex(nodeNum);
    final altitude = event.altitude ?? existing?.altitudeM ?? 0;
    final calculated = _buildNodeTelemetry(
      nodeNum: nodeNum,
      callSign: callSign,
      latitude: latitude,
      longitude: longitude,
      altitudeM: altitude,
      heardAt: _latest(event.heardAt ?? DateTime.now(), existing?.lastSeenAt),
      existingBattery: existing?.batteryPercent,
    );

    if (existingIndex == -1) {
      _nodes.add(calculated);
    } else {
      _nodes[existingIndex] = calculated.copyWith(
        batteryPercent: existing!.batteryPercent,
      );
    }
    return true;
  }

  String? _eventCallSign(DecodedMeshEvent event) {
    final shortName = event.shortName?.trim();
    if (shortName != null && shortName.isNotEmpty) {
      return shortName;
    }
    final longName = event.longName?.trim();
    if (longName != null && longName.isNotEmpty) {
      return longName;
    }
    return null;
  }

  MeshNode _buildNodeTelemetry({
    required int nodeNum,
    required String callSign,
    required double latitude,
    required double longitude,
    required int altitudeM,
    required DateTime heardAt,
    int? existingBattery,
  }) {
    final self = _selfNode;
    final distanceKm = _distanceKm(
      self.latitude,
      self.longitude,
      latitude,
      longitude,
    );
    final bearingDeg = _bearingDeg(
      self.latitude,
      self.longitude,
      latitude,
      longitude,
    );
    return MeshNode(
      nodeNum: nodeNum,
      callSign: callSign,
      latitude: latitude,
      longitude: longitude,
      altitudeM: altitudeM,
      mgrs: _mgrsLabel(latitude, longitude),
      batteryPercent: existingBattery ?? 100,
      lastSeenAt: heardAt,
      distanceKm: distanceKm,
      bearingDeg: bearingDeg,
      mapOffset: Offset(
        ((longitude - self.longitude) * 18).clamp(-1.0, 1.0),
        ((self.latitude - latitude) * 18).clamp(-1.0, 1.0),
      ),
    );
  }

  DateTime _latest(DateTime value, DateTime? other) {
    if (other == null || value.isAfter(other)) {
      return value;
    }
    return other;
  }

  bool _appendIncomingMeshMessage(DecodedMeshEvent event) {
    final text = event.text?.trim();
    if (text == null || text.isEmpty) {
      return false;
    }

    // Duplicate deliveries (rebroadcasts, re-read queue) share from+id.
    final packetId = event.packetId;
    if (packetId != null &&
        packetId != 0 &&
        _messages.any(
          (message) =>
              message.delivery == MessageDelivery.received &&
              message.packetId == packetId &&
              message.fromNode == event.from,
        )) {
      return false;
    }

    // Unknown channel indexes land in the primary channel group; the selected
    // index refers to the session's allowed groups, not to _groups.
    final group = _groups.firstWhere(
      (group) => group.channelIndex == event.channelIndex,
      orElse: () => _groups.firstWhere(
        (group) => group.channelIndex == 0,
        orElse: () => _groups.first,
      ),
    );
    final sender = _nodeCallSign(event.from) ?? _nodeHex(event.from);
    final target = event.to == meshtasticBroadcastNode
        ? group.name
        : 'DM ${_nodeCallSign(event.to) ?? _nodeHex(event.to)}';
    _messages.insert(
      0,
      MeshMessage(
        sender: sender,
        body: text,
        time: _clockLabel(DateTime.now()),
        groupId: group.id,
        targetLabel: target,
        packetId: packetId,
        fromNode: event.from,
      ),
    );
    return true;
  }

  Future<void> _sendMeshText(
    MeshMessageDraft draft,
    List<CommunicationGroup> groups,
  ) async {
    final group = groups.firstWhere((item) => item.id == draft.groupId);
    final directNode = draft.directNode;
    final target = directNode == null
        ? group.name
        : 'DM ${directNode.callSign}';
    final outgoingMessage = MeshMessage(
      sender: _selfNode.callSign,
      body: draft.text,
      time: _clockLabel(DateTime.now()),
      groupId: draft.groupId,
      targetLabel: target,
      delivery: MessageDelivery.sending,
      priority: draft.priority,
      packetId: _newPacketId(),
      fromNode: _selfNode.nodeNum,
      toNode: directNode?.nodeNum,
    );
    setState(() {
      _messages.insert(0, outgoingMessage);
    });
    await _transmit(outgoingMessage);
  }

  Future<void> _retryMessage(MeshMessage message) async {
    final packetId = message.packetId;
    if (!message.canRetry || packetId == null) {
      return;
    }
    // A fresh id so a late ACK for the previous attempt cannot be confused
    // with this one.
    final retry = message.copyWith(
      delivery: MessageDelivery.sending,
      packetId: _newPacketId(),
    );
    final replaced = _replaceOutgoing(packetId, (_) => retry);
    if (replaced) {
      await _transmit(retry);
    }
  }

  Future<void> _transmit(MeshMessage message) async {
    final packetId = message.packetId!;
    final channelIndex = _groups
        .firstWhere(
          (group) => group.id == message.groupId,
          orElse: () => _groups.first,
        )
        .channelIndex;
    final toNode = message.toNode;
    final bytes = toNode == null
        ? _messageEncoder.encodeGroupText(
            text: message.body,
            channelIndex: channelIndex,
            packetId: packetId,
          )
        : _messageEncoder.encodeDirectText(
            text: message.body,
            destinationNode: toNode,
            channelIndex: channelIndex,
            packetId: packetId,
          );
    unawaited(_persistState());

    var delivery = MessageDelivery.sent;
    try {
      await _meshtasticBleService.writeToRadio(bytes);
    } catch (error) {
      delivery = MessageDelivery.notSent;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'T-Beam není připojen: zprávu lze odeslat znovu ze seznamu.',
            ),
            backgroundColor: dangerRed,
          ),
        );
      }
    }

    if (!mounted) {
      return;
    }
    _replaceOutgoing(
      packetId,
      (current) => current.delivery == MessageDelivery.sending
          ? current.copyWith(delivery: delivery)
          : current,
    );
  }

  /// Replaces our own outgoing message carrying [packetId]; returns false
  /// when it is no longer in the list.
  bool _replaceOutgoing(
    int packetId,
    MeshMessage Function(MeshMessage current) update,
  ) {
    final index = _messages.indexWhere(
      (message) =>
          message.packetId == packetId &&
          message.delivery != MessageDelivery.received,
    );
    if (index == -1) {
      return false;
    }
    setState(() => _messages[index] = update(_messages[index]));
    unawaited(_persistState());
    return true;
  }

  bool _applyRoutingResult(DecodedMeshEvent event) {
    final requestId = event.requestId;
    if (requestId == null || requestId == 0) {
      return false;
    }
    final index = _messages.indexWhere(
      (message) =>
          message.packetId == requestId &&
          message.delivery != MessageDelivery.received,
    );
    if (index == -1) {
      return false;
    }
    final current = _messages[index];
    if (current.delivery == MessageDelivery.delivered) {
      return false;
    }
    _messages[index] = current.copyWith(
      delivery: event.routingError == 0
          ? MessageDelivery.delivered
          : MessageDelivery.failed,
    );
    return true;
  }

  int _newPacketId() => _packetIdRandom.nextInt(0x7FFFFFFF) + 1;

  Future<void> _shareWaypoint(
    TacticalWaypoint waypoint,
    List<CommunicationGroup> groups,
  ) async {
    final text =
        'WP ${waypoint.code} | ${waypoint.typeLabel} | MGRS ${waypoint.mgrs} | LAT ${waypoint.latitude.toStringAsFixed(6)} | LON ${waypoint.longitude.toStringAsFixed(6)} | ${waypoint.note}';
    await _sendMeshText(
      MeshMessageDraft(
        text: text,
        groupId: groups[_selectedGroupIndex].id,
        priority: waypoint.priority,
      ),
      groups,
    );
  }

  Future<void> _sendCheckIn(
    MeshNode node,
    List<CommunicationGroup> groups,
  ) async {
    final text =
        'CHECK-IN | ${node.callSign} | LAST ${node.lastSeenMinutes} min | MGRS ${node.mgrs} | STATUS ${node.linkStatus.label}';
    await _sendMeshText(
      MeshMessageDraft(
        text: text,
        groupId: groups[_selectedGroupIndex].id,
        directNode: node,
        priority: node.linkStatus != MeshNodeLinkStatus.ok,
      ),
      groups,
    );
  }

  Future<void> _restorePersistedState(String userName) async {
    try {
      final snapshot = await _stateStore.load();
      if (!mounted || snapshot == null) {
        return;
      }
      // A snapshot left behind by another user (app killed without logout)
      // must not leak into this session.
      final owner = snapshot.owner;
      if (owner != null && owner != userName) {
        await _stateStore.clear();
        return;
      }

      final restoredNodes = snapshot.nodes
          .map(MeshNode.fromJson)
          .where((node) => node.isSelf || node.nodeNum != _selfNode.nodeNum)
          .toList();
      final restoredMessages = snapshot.messages
          .map(MeshMessage.fromJson)
          .toList();
      if (restoredNodes.isEmpty && restoredMessages.isEmpty) {
        return;
      }

      setState(() {
        if (restoredNodes.any((node) => node.isSelf)) {
          _nodes
            ..clear()
            ..addAll(restoredNodes);
        }
        if (restoredMessages.isNotEmpty) {
          _messages
            ..clear()
            ..addAll(restoredMessages);
        }
      });
      final liveFix = _locationState.lastFix;
      if (liveFix != null) {
        _applySelfFix(liveFix);
      }
    } catch (_) {
      // Ignore corrupt or incompatible local state and keep demo defaults.
    }
  }

  Future<void> _persistState() async {
    final session = _session;
    if (session == null) {
      return;
    }
    try {
      await _stateStore.save(
        nodes: [for (final node in _nodes) node.toJson()],
        messages: [for (final message in _messages.take(150)) message.toJson()],
        owner: session.userName,
      );
    } catch (_) {
      // Persistence is best effort; the live session keeps working.
    }
  }

  String _clockLabel(DateTime value) {
    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(value.hour)}:${two(value.minute)}';
  }

  String? _nodeCallSign(int? nodeNum) {
    if (nodeNum == null) {
      return null;
    }
    for (final node in _nodes) {
      if (node.nodeNum == nodeNum) {
        return node.callSign;
      }
    }
    return null;
  }

  String _nodeHex(int? nodeNum) {
    if (nodeNum == null) {
      return '!UNKNOWN';
    }
    return '!${nodeNum.toRadixString(16).padLeft(8, '0').toUpperCase()}';
  }

  String _mgrsLabel(double latitude, double longitude) {
    final raw = Mgrs.forward([longitude, latitude], 5).toUpperCase();
    final match = RegExp(
      r'^(\d{1,2}[C-X])([A-Z]{2})(\d{5})(\d{5})$',
    ).firstMatch(raw);
    if (match == null) {
      return raw;
    }
    return '${match.group(1)} ${match.group(2)} ${match.group(3)} ${match.group(4)}';
  }

  double _distanceKm(
    double fromLat,
    double fromLon,
    double toLat,
    double toLon,
  ) {
    const earthRadiusKm = 6371.0;
    final dLat = radians(toLat - fromLat);
    final dLon = radians(toLon - fromLon);
    final lat1 = radians(fromLat);
    final lat2 = radians(toLat);
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return earthRadiusKm * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  double _bearingDeg(
    double fromLat,
    double fromLon,
    double toLat,
    double toLon,
  ) {
    final lat1 = radians(fromLat);
    final lat2 = radians(toLat);
    final dLon = radians(toLon - fromLon);
    final y = math.sin(dLon) * math.cos(lat2);
    final x =
        math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
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
