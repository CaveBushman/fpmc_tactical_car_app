import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:mgrs_dart/mgrs_dart.dart';

import 'services/auth_service.dart';
import 'services/encrypted_ptt_service.dart';
import 'services/mesh_packet_repository.dart';
import 'services/meshtastic_packet_decoder.dart';
import 'services/meshtastic_message_encoder.dart';
import 'services/meshtastic_ble_service.dart';
import 'services/ptt_access_service.dart';
import 'services/tactical_state_store.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  BuiltInMapCachingProvider.getOrCreateInstance(
    maxCacheSize: 512 * 1024 * 1024,
    overrideFreshAge: const Duration(days: 30),
  );
  runApp(const TacticalCarApp());
}

const rangerGreen = Color(0xFF4B5320);
const fieldBlack = Color(0xFF11140E);
const panelGreen = Color(0xFF1B2117);
const sand = Color(0xFFC2B280);
const tacticalKhaki = Color(0xFF8F8B5E);
const signalAmber = tacticalKhaki;
const dangerRed = Color(0xFFE2504C);
const blueForce = Color(0xFF5FA8D3);
const pmcLogoAsset = 'assets/branding/1stpmc_logo_ral6031.png';
const tacticalMapUrlTemplate = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

class TacticalCarApp extends StatelessWidget {
  const TacticalCarApp({super.key});

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
      home: const TacticalHomeScreen(),
    );
  }
}

class TacticalHomeScreen extends StatefulWidget {
  const TacticalHomeScreen({super.key});

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
  StreamSubscription<MeshtasticBleState>? _bleStateSubscription;
  StreamSubscription<MeshtasticBlePacket>? _blePacketSubscription;
  StreamSubscription<MeshPacketDiagnostics>? _packetDiagnosticsSubscription;
  StreamSubscription<List<DecodedMeshEvent>>? _meshEventsSubscription;
  StreamSubscription<EncryptedPttState>? _pttStateSubscription;
  DateTime _now = DateTime.now();
  int _selectedIndex = 0;
  bool _pttActive = false;
  bool _internetVoiceOnline = true;
  bool _meshConnected = true;
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

  final List<MeshNode> _nodes = [...MeshNode.demoNodes];
  final List<MeshMessage> _messages = [...MeshMessage.demoMessages];
  final List<CommunicationGroup> _groups = CommunicationGroup.demoGroups;
  final List<TacticalWaypoint> _waypoints = TacticalWaypoint.demoWaypoints;

  @override
  void initState() {
    super.initState();
    _authService = AuthService();
    _pttAccessService = const PttAccessService();
    _meshtasticBleService = MeshtasticBleService();
    _messageEncoder = const MeshtasticMessageEncoder();
    _meshPacketRepository = MeshPacketRepository();
    _pttService = EncryptedPttService(channel: 'ALPHA');
    _stateStore = const TacticalStateStore();
    unawaited(_restorePersistedState());
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
        onShareWaypoint: (waypoint) => _shareWaypoint(waypoint, allowedGroups),
      ),
      TeamPage(nodes: _nodes),
      MessagesPage(
        messages: _messages,
        groups: allowedGroups,
        nodes: _nodes.where((node) => !node.isSelf).toList(),
        selfNode: _selfNode,
        selectedGroupIndex: _selectedGroupIndex,
        onGroupSelected: (index) => _selectGroup(index, allowedGroups),
        onSend: (draft) => _sendMeshText(draft, allowedGroups),
      ),
      SystemsPage(
        meshConnected: _meshConnected,
        internetVoiceOnline: _internetVoiceOnline,
        onMeshChanged: (value) => setState(() => _meshConnected = value),
        onVoiceChanged: (value) => setState(() => _internetVoiceOnline = value),
        onBleConnect: _meshtasticBleService.startAutoConnect,
        bleState: _bleState,
        packetDiagnostics: _packetDiagnostics,
        pttState: _pttState,
        fontScale: _fontScale,
        onFontScaleChanged: (value) => setState(() => _fontScale = value),
      ),
    ];

    final landscapePages = [
      const SizedBox.shrink(),
      TeamPage(nodes: _nodes),
      MessagesPage(
        messages: _messages,
        groups: allowedGroups,
        nodes: _nodes.where((node) => !node.isSelf).toList(),
        selfNode: _selfNode,
        selectedGroupIndex: _selectedGroupIndex,
        onGroupSelected: (index) => _selectGroup(index, allowedGroups),
        onSend: (draft) => _sendMeshText(draft, allowedGroups),
      ),
      SystemsPage(
        meshConnected: _meshConnected,
        internetVoiceOnline: _internetVoiceOnline,
        onMeshChanged: (value) => setState(() => _meshConnected = value),
        onVoiceChanged: (value) => setState(() => _internetVoiceOnline = value),
        onBleConnect: _meshtasticBleService.startAutoConnect,
        bleState: _bleState,
        packetDiagnostics: _packetDiagnostics,
        pttState: _pttState,
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
    _syncPttChannelForGroup(
      result.session!,
      _groups.firstWhere(
        (group) => group.id == result.session!.allowedGroupIds.first,
      ),
    );
    return null;
  }

  Future<void> _logout() async {
    await _authService.logout();
    setState(() {
      _session = null;
      _selectedGroupIndex = 0;
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

  void _applyDecodedMeshEvents(List<DecodedMeshEvent> events) {
    if (!mounted) {
      return;
    }

    var changed = false;
    setState(() {
      for (final event in events) {
        switch (event.type) {
          case DecodedMeshEventType.nodeInfo:
          case DecodedMeshEventType.position:
            changed = _upsertMeshNode(event) || changed;
          case DecodedMeshEventType.textMessage:
            changed = _appendIncomingMeshMessage(event) || changed;
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

  bool _upsertMeshNode(DecodedMeshEvent event) {
    final nodeNum = event.nodeNum ?? event.from;
    if (nodeNum == null || nodeNum == _selfNode.nodeNum) {
      return false;
    }

    final existingIndex = _nodes.indexWhere((node) => node.nodeNum == nodeNum);
    final existing = existingIndex == -1 ? null : _nodes[existingIndex];
    final latitude = event.latitude ?? existing?.latitude;
    final longitude = event.longitude ?? existing?.longitude;
    if (latitude == null || longitude == null) {
      return false;
    }

    final callSign = event.shortName?.trim().isNotEmpty == true
        ? event.shortName!.trim()
        : event.longName?.trim().isNotEmpty == true
        ? event.longName!.trim()
        : existing?.callSign ?? _nodeHex(nodeNum);
    final altitude = event.altitude ?? existing?.altitudeM ?? 0;
    final calculated = _buildNodeTelemetry(
      nodeNum: nodeNum,
      callSign: callSign,
      latitude: latitude,
      longitude: longitude,
      altitudeM: altitude,
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

  MeshNode _buildNodeTelemetry({
    required int nodeNum,
    required String callSign,
    required double latitude,
    required double longitude,
    required int altitudeM,
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
      lastSeenMinutes: 0,
      distanceKm: distanceKm,
      bearingDeg: bearingDeg,
      mapOffset: Offset(
        ((longitude - self.longitude) * 18).clamp(-1.0, 1.0),
        ((self.latitude - latitude) * 18).clamp(-1.0, 1.0),
      ),
    );
  }

  bool _appendIncomingMeshMessage(DecodedMeshEvent event) {
    final text = event.text?.trim();
    if (text == null || text.isEmpty) {
      return false;
    }

    final group = _groups.firstWhere(
      (group) => group.channelIndex == event.channelIndex,
      orElse: () => _groups[_selectedGroupIndex],
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
      ),
    );
    return true;
  }

  Future<void> _sendMeshText(
    MeshMessageDraft draft,
    List<CommunicationGroup> groups,
  ) async {
    final group = groups.firstWhere((item) => item.id == draft.groupId);
    final bytes = draft.directNode == null
        ? _messageEncoder.encodeGroupText(
            text: draft.text,
            channelIndex: group.channelIndex,
          )
        : _messageEncoder.encodeDirectText(
            text: draft.text,
            destinationNode: draft.directNode!.nodeNum,
            channelIndex: group.channelIndex,
          );

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
      pending: true,
      priority: draft.priority,
    );
    setState(() {
      _messages.insert(0, outgoingMessage);
    });
    unawaited(_persistState());

    try {
      await _meshtasticBleService.writeToRadio(bytes);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('T-Beam není připojen: zpráva je jen lokálně.'),
            backgroundColor: dangerRed,
          ),
        );
      }
      return;
    }

    if (!mounted) {
      return;
    }
    setState(() {
      final index = _messages.indexOf(outgoingMessage);
      if (index != -1) {
        _messages[index] = MeshMessage(
          sender: outgoingMessage.sender,
          body: outgoingMessage.body,
          time: outgoingMessage.time,
          groupId: outgoingMessage.groupId,
          targetLabel: outgoingMessage.targetLabel,
          priority: outgoingMessage.priority,
        );
      }
    });
    unawaited(_persistState());
  }

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

  Future<void> _restorePersistedState() async {
    try {
      final snapshot = await _stateStore.load();
      if (!mounted || snapshot == null) {
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
    } catch (_) {
      // Ignore corrupt or incompatible local state and keep demo defaults.
    }
  }

  Future<void> _persistState() async {
    await _stateStore.save(
      nodes: [for (final node in _nodes) node.toJson()],
      messages: [for (final message in _messages.take(150)) message.toJson()],
    );
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

class LoginScreen extends StatefulWidget {
  const LoginScreen({required this.onLogin, super.key});

  final Future<String?> Function(String userName, String password) onLogin;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _userController = TextEditingController(
    text: 'operator',
  );
  final TextEditingController _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _submitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _userController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        height: 54,
                        width: 86,
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: rangerGreen.withValues(alpha: 0.8),
                          ),
                        ),
                        child: Image.asset(pmcLogoAsset, fit: BoxFit.contain),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'FIRST PRIVATE MILITARY COMPANY',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),
                  TextField(
                    controller: _userController,
                    enabled: !_submitting,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Uživatel',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _passwordController,
                    enabled: !_submitting,
                    obscureText: _obscurePassword,
                    onSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      labelText: 'Heslo',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        tooltip: _obscurePassword
                            ? 'Zobrazit heslo'
                            : 'Skrýt heslo',
                        onPressed: () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                  ),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      _errorMessage!,
                      style: const TextStyle(
                        color: dangerRed,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _submitting ? null : _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: rangerGreen,
                      minimumSize: const Size.fromHeight(52),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    icon: Icon(_submitting ? Icons.hourglass_top : Icons.login),
                    label: Text(_submitting ? 'Ověřuji' : 'Přihlásit'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final userName = _userController.text.trim();
    if (userName.isEmpty) {
      setState(() => _errorMessage = 'Zadej uživatele.');
      return;
    }
    setState(() {
      _submitting = true;
      _errorMessage = null;
    });
    final error = await widget.onLogin(userName, _passwordController.text);
    if (!mounted) {
      return;
    }
    setState(() {
      _submitting = false;
      _errorMessage = error;
    });
  }
}

class UserSessionChip extends StatelessWidget {
  const UserSessionChip({
    required this.session,
    required this.onLogout,
    super.key,
  });

  final AuthSession session;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Uživatel',
      onSelected: (value) {
        if (value == 'logout') {
          onLogout();
        }
      },
      itemBuilder: (context) => const [
        PopupMenuItem(value: 'logout', child: Text('Odhlásit')),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: panelGreen,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Row(
          children: [
            const Icon(Icons.verified_user_outlined, size: 16, color: sand),
            const SizedBox(width: 6),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  session.displayName,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  session.role,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.white.withValues(alpha: 0.62),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class TacticalNavigationRail extends StatelessWidget {
  const TacticalNavigationRail({
    required this.selectedIndex,
    required this.onDestinationSelected,
    super.key,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    return NavigationRail(
      backgroundColor: const Color(0xFF171B13),
      indicatorColor: rangerGreen.withValues(alpha: 0.85),
      selectedIndex: selectedIndex,
      onDestinationSelected: onDestinationSelected,
      labelType: NavigationRailLabelType.none,
      minWidth: 64,
      destinations: const [
        NavigationRailDestination(
          icon: Icon(Icons.map_outlined),
          selectedIcon: Icon(Icons.map),
          label: Text('Mapa'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.groups_2_outlined),
          selectedIcon: Icon(Icons.groups_2),
          label: Text('Tým'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.chat_bubble_outline),
          selectedIcon: Icon(Icons.chat_bubble),
          label: Text('Zprávy'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.settings_outlined),
          selectedIcon: Icon(Icons.settings),
          label: Text('Systém'),
        ),
      ],
    );
  }
}

class AppBrand extends StatelessWidget {
  const AppBrand({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          height: 36,
          width: 58,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: rangerGreen.withValues(alpha: 0.8)),
          ),
          child: Image.asset(
            pmcLogoAsset,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
          ),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            'FIRST PRIVATE MILITARY COMPANY',
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }
}

class TimeReadout extends StatelessWidget {
  const TimeReadout({required this.now, super.key});

  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final utc = now.toUtc();
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          'LOC ${_time(now)}',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
        Text(
          'UTC ${_time(utc)}',
          style: TextStyle(
            fontSize: 11,
            color: Colors.white.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }

  String _time(DateTime value) {
    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(value.hour)}:${two(value.minute)}:${two(value.second)}';
  }
}

class StatusStrip extends StatelessWidget {
  const StatusStrip({
    required this.meshConnected,
    required this.voiceOnline,
    required this.pttActive,
    super.key,
  });

  final bool meshConnected;
  final bool voiceOnline;
  final bool pttActive;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 2, 12, 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: panelGreen,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Expanded(
            child: StatusChip(
              icon: Icons.bluetooth_connected,
              label: 'T-Beam 868',
              ok: meshConnected,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: StatusChip(
              icon: Icons.cloud_done_outlined,
              label: 'PTT server',
              ok: voiceOnline,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: StatusChip(
              icon: pttActive ? Icons.mic : Icons.mic_none,
              label: pttActive ? 'Vysílám' : 'Příjem',
              ok: !pttActive,
              alert: pttActive,
            ),
          ),
        ],
      ),
    );
  }
}

class StatusChip extends StatelessWidget {
  const StatusChip({
    required this.icon,
    required this.label,
    required this.ok,
    this.alert = false,
    super.key,
  });

  final IconData icon;
  final String label;
  final bool ok;
  final bool alert;

  @override
  Widget build(BuildContext context) {
    final color = alert ? signalAmber : (ok ? sand : dangerRed);
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 17, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class MapPage extends StatelessWidget {
  const MapPage({
    required this.nodes,
    required this.waypoints,
    required this.pttActive,
    required this.onShareWaypoint,
    this.compact = false,
    super.key,
  });

  final List<MeshNode> nodes;
  final List<TacticalWaypoint> waypoints;
  final bool pttActive;
  final ValueChanged<TacticalWaypoint> onShareWaypoint;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final self = nodes.firstWhere((node) => node.isSelf);
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
                      child: CoordinatePanel(node: self, compact: true),
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
            const SizedBox(height: 8),
            SizedBox(
              height: 78,
              child: Row(
                children: [
                  Expanded(
                    child: MetricTile(
                      label: 'Uzly',
                      value: '${nodes.length}',
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
                      label: 'Nejbližší',
                      value:
                          '${_nearest(nodes).distanceKm.toStringAsFixed(1)} km',
                      icon: Icons.near_me_outlined,
                      compact: true,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: MetricTile(
                      label: 'Fallback',
                      value: 'LoRa',
                      icon: Icons.sms_outlined,
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
                  child: CoordinatePanel(node: self),
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
              label: 'Aktivní uzly',
              value: '${nodes.length}',
              icon: Icons.hub_outlined,
            ),
            const MetricTile(label: 'Kanál', value: 'ALPHA', icon: Icons.radio),
            MetricTile(
              label: 'Nejbližší',
              value: '${_nearest(nodes).distanceKm.toStringAsFixed(1)} km',
              icon: Icons.near_me_outlined,
            ),
            const MetricTile(
              label: 'Fallback',
              value: 'LoRa text',
              icon: Icons.sms_outlined,
            ),
          ],
        ),
        const SizedBox(height: 10),
        WaypointStrip(waypoints: waypoints, onShareWaypoint: onShareWaypoint),
      ],
    );
  }

  MeshNode _nearest(List<MeshNode> nodes) {
    final others = nodes.where((node) => !node.isSelf).toList()
      ..sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
    return others.first;
  }
}

class MeshMap extends StatelessWidget {
  const MeshMap({required this.nodes, required this.waypoints, super.key});

  final List<MeshNode> nodes;
  final List<TacticalWaypoint> waypoints;

  @override
  Widget build(BuildContext context) {
    final self = nodes.firstWhere((node) => node.isSelf);
    final selfPoint = self.latLng;
    return Stack(
      children: [
        FlutterMap(
          options: MapOptions(
            initialCenter: selfPoint,
            initialZoom: 13.4,
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
    final color = node.isSelf ? tacticalKhaki : blueForce;
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
          child: Text(
            node.callSign,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w900,
            ),
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

class CoordinatePanel extends StatelessWidget {
  const CoordinatePanel({required this.node, this.compact = false, super.key});

  final MeshNode node;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: compact ? 260 : 285,
      padding: EdgeInsets.all(compact ? 10 : 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: rangerGreen.withValues(alpha: 0.65)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'VLASTNÍ POZICE',
            style: TextStyle(
              fontSize: compact ? 10 : 11,
              color: sand,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: compact ? 6 : 8),
          MgrsReadout(value: node.mgrs, compact: compact),
          SizedBox(height: compact ? 4 : 6),
          MonoLine(label: 'LAT', value: node.latitude.toStringAsFixed(6)),
          MonoLine(label: 'LON', value: node.longitude.toStringAsFixed(6)),
          if (!compact) MonoLine(label: 'ALT', value: '${node.altitudeM} m'),
        ],
      ),
    );
  }
}

class MgrsReadout extends StatelessWidget {
  const MgrsReadout({required this.value, required this.compact, super.key});

  final String value;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final parts = value
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    final fields = parts.length >= 4
        ? [
            _MgrsField(label: 'ZONE', value: parts[0]),
            _MgrsField(label: 'GRID', value: parts[1]),
            _MgrsField(label: 'EAST', value: parts[2]),
            _MgrsField(label: 'NORTH', value: parts[3]),
          ]
        : [_MgrsField(label: 'MGRS', value: value)];
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 9 : 10,
        vertical: compact ? 7 : 8,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.38),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: tacticalKhaki.withValues(alpha: 0.26)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'MGRS',
            style: TextStyle(
              fontSize: compact ? 10 : 11,
              color: sand,
              fontWeight: FontWeight.w900,
            ),
          ),
          SizedBox(height: compact ? 4 : 5),
          for (final field in fields)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: compact ? 48 : 54,
                    child: Text(
                      field.label,
                      style: TextStyle(
                        fontSize: compact ? 10 : 11,
                        height: 1.1,
                        color: Colors.white.withValues(alpha: 0.58),
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      field.value,
                      maxLines: 1,
                      overflow: TextOverflow.visible,
                      softWrap: false,
                      style: TextStyle(
                        fontSize: compact ? 14 : 15,
                        height: 1.1,
                        color: Colors.white,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _MgrsField {
  const _MgrsField({required this.label, required this.value});

  final String label;
  final String value;
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

class WaypointStrip extends StatelessWidget {
  const WaypointStrip({
    required this.waypoints,
    required this.onShareWaypoint,
    this.compact = false,
    super.key,
  });

  final List<TacticalWaypoint> waypoints;
  final ValueChanged<TacticalWaypoint> onShareWaypoint;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: waypoints.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) => SizedBox(
          width: 235,
          child: WaypointCard(
            waypoint: waypoints[index],
            onShare: () => onShareWaypoint(waypoints[index]),
            compact: true,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Body mise',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        for (final waypoint in waypoints) ...[
          WaypointCard(
            waypoint: waypoint,
            onShare: () => onShareWaypoint(waypoint),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class WaypointCard extends StatelessWidget {
  const WaypointCard({
    required this.waypoint,
    required this.onShare,
    this.compact = false,
    super.key,
  });

  final TacticalWaypoint waypoint;
  final VoidCallback onShare;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final color = waypoint.priority ? dangerRed : sand;
    return Card(
      child: Padding(
        padding: EdgeInsets.all(compact ? 9 : 12),
        child: Row(
          children: [
            Container(
              height: compact ? 34 : 40,
              width: compact ? 34 : 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: color.withValues(alpha: 0.38)),
              ),
              child: Icon(waypoint.icon, color: color, size: compact ? 18 : 21),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${waypoint.code} | ${waypoint.typeLabel}',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: compact ? 12 : 14,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    waypoint.mgrs,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: sand,
                      fontSize: compact ? 11 : 12,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (!compact) ...[
                    const SizedBox(height: 2),
                    Text(
                      waypoint.note,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.66),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            IconButton.filled(
              tooltip: 'Sdílet ${waypoint.code}',
              onPressed: onShare,
              style: IconButton.styleFrom(
                backgroundColor: rangerGreen,
                foregroundColor: Colors.white,
                fixedSize: Size(compact ? 38 : 42, compact ? 38 : 42),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              icon: const Icon(Icons.send, size: 18),
            ),
          ],
        ),
      ),
    );
  }
}

class TeamPage extends StatelessWidget {
  const TeamPage({required this.nodes, super.key});

  final List<MeshNode> nodes;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      itemCount: nodes.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) => NodeCard(node: nodes[index]),
    );
  }
}

class NodeCard extends StatelessWidget {
  const NodeCard({required this.node, super.key});

  final MeshNode node;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: node.isSelf ? signalAmber : blueForce,
              foregroundColor: Colors.black,
              child: Text(
                node.callSign.characters.first,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    node.callSign,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    node.mgrs,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      color: sand,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${node.distanceKm.toStringAsFixed(1)} km | ${node.bearingDeg.toStringAsFixed(0)} deg | ${node.lastSeenMinutes} min',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.68),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            BatteryBadge(percent: node.batteryPercent),
          ],
        ),
      ),
    );
  }
}

class MessagesPage extends StatefulWidget {
  const MessagesPage({
    required this.messages,
    required this.groups,
    required this.nodes,
    required this.selfNode,
    required this.selectedGroupIndex,
    required this.onGroupSelected,
    required this.onSend,
    super.key,
  });

  final List<MeshMessage> messages;
  final List<CommunicationGroup> groups;
  final List<MeshNode> nodes;
  final MeshNode selfNode;
  final int selectedGroupIndex;
  final ValueChanged<int> onGroupSelected;
  final Future<void> Function(MeshMessageDraft draft) onSend;

  @override
  State<MessagesPage> createState() => _MessagesPageState();
}

class _MessagesPageState extends State<MessagesPage> {
  final TextEditingController _textController = TextEditingController();
  bool _directMode = false;
  int _selectedNodeIndex = 0;

  @override
  void didUpdateWidget(covariant MessagesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_selectedNodeIndex >= widget.nodes.length) {
      _selectedNodeIndex = 0;
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedGroup = widget.groups[widget.selectedGroupIndex];
    final filteredMessages = widget.messages
        .where((message) => message.groupId == selectedGroup.id)
        .toList();
    return Column(
      children: [
        SizedBox(
          height: 72,
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            scrollDirection: Axis.horizontal,
            itemCount: widget.groups.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final group = widget.groups[index];
              final selected = index == widget.selectedGroupIndex;
              return ChoiceChip(
                selected: selected,
                onSelected: (_) => widget.onGroupSelected(index),
                avatar: Icon(
                  group.icon,
                  size: 18,
                  color: selected ? sand : sand.withValues(alpha: 0.82),
                ),
                label: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      group.name,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    Text(
                      group.transportLabel,
                      style: const TextStyle(fontSize: 11),
                    ),
                  ],
                ),
                labelPadding: const EdgeInsets.symmetric(horizontal: 8),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                selectedColor: rangerGreen.withValues(alpha: 0.95),
                backgroundColor: panelGreen,
                side: BorderSide(
                  color: selected
                      ? tacticalKhaki.withValues(alpha: 0.8)
                      : Colors.white.withValues(alpha: 0.12),
                ),
              );
            },
          ),
        ),
        MessageComposer(
          controller: _textController,
          directMode: _directMode,
          nodes: widget.nodes,
          selectedNodeIndex: _selectedNodeIndex,
          selectedGroup: selectedGroup,
          onModeChanged: (value) => setState(() => _directMode = value),
          onNodeChanged: (index) => setState(() => _selectedNodeIndex = index),
          onSend: _send,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: QuickActionButton(
                  label: 'OK',
                  icon: Icons.check_circle_outline,
                  onPressed: () => _sendQuickMessage('OK'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: QuickActionButton(
                  label: 'NA POZICI',
                  icon: Icons.place_outlined,
                  onPressed: _sendPositionReport,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: QuickActionButton(
                  label: 'SOS',
                  icon: Icons.warning_amber_outlined,
                  danger: true,
                  onPressed: () => _sendQuickMessage('SOS', priority: true),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            itemCount: filteredMessages.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) =>
                MessageCard(message: filteredMessages[index]),
          ),
        ),
      ],
    );
  }

  Future<void> _send() async {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      return;
    }

    final directNode = _directMode && widget.nodes.isNotEmpty
        ? widget.nodes[_selectedNodeIndex]
        : null;
    await widget.onSend(
      MeshMessageDraft(
        text: text,
        groupId: widget.groups[widget.selectedGroupIndex].id,
        directNode: directNode,
      ),
    );
    _textController.clear();
  }

  Future<void> _sendQuickMessage(String text, {bool priority = false}) async {
    await widget.onSend(
      MeshMessageDraft(
        text: text,
        groupId: widget.groups[widget.selectedGroupIndex].id,
        priority: priority,
      ),
    );
  }

  Future<void> _sendPositionReport() async {
    final self = widget.selfNode;
    final text =
        'NA POZICI | MGRS ${self.mgrs} | LAT ${self.latitude.toStringAsFixed(6)} | LON ${self.longitude.toStringAsFixed(6)}';
    await _sendQuickMessage(text);
  }
}

class MessageComposer extends StatelessWidget {
  const MessageComposer({
    required this.controller,
    required this.directMode,
    required this.nodes,
    required this.selectedNodeIndex,
    required this.selectedGroup,
    required this.onModeChanged,
    required this.onNodeChanged,
    required this.onSend,
    super.key,
  });

  final TextEditingController controller;
  final bool directMode;
  final List<MeshNode> nodes;
  final int selectedNodeIndex;
  final CommunicationGroup selectedGroup;
  final ValueChanged<bool> onModeChanged;
  final ValueChanged<int> onNodeChanged;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final canSendDirect = nodes.isNotEmpty;
    final selectedNode = canSendDirect ? nodes[selectedNodeIndex] : null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.22),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Column(
          children: [
            Row(
              children: [
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                      value: false,
                      icon: Icon(Icons.groups_2, size: 17),
                      label: Text('Skupina'),
                    ),
                    ButtonSegment(
                      value: true,
                      icon: Icon(Icons.person_pin_circle, size: 17),
                      label: Text('Osoba'),
                    ),
                  ],
                  selected: {directMode},
                  onSelectionChanged: (value) =>
                      onModeChanged(value.single && canSendDirect),
                  style: ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: WidgetStateProperty.resolveWith(
                      (states) => states.contains(WidgetState.selected)
                          ? Colors.white
                          : sand,
                    ),
                    backgroundColor: WidgetStateProperty.resolveWith(
                      (states) => states.contains(WidgetState.selected)
                          ? rangerGreen
                          : Colors.transparent,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: directMode
                      ? DropdownButtonFormField<int>(
                          initialValue: selectedNodeIndex,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            isDense: true,
                            labelText: 'Adresát',
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            for (var index = 0; index < nodes.length; index++)
                              DropdownMenuItem(
                                value: index,
                                child: Text(
                                  '${nodes[index].callSign} / !${nodes[index].nodeNum.toRadixString(16).padLeft(8, '0').toUpperCase()}',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              onNodeChanged(value);
                            }
                          },
                        )
                      : _TargetPill(
                          icon: Icons.radio,
                          label:
                              '${selectedGroup.name} / kanál ${selectedGroup.channelIndex}',
                        ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    minLines: 1,
                    maxLines: 3,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => onSend(),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: directMode && selectedNode != null
                          ? 'Zpráva pro ${selectedNode.callSign}'
                          : 'Zpráva skupině ${selectedGroup.name}',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: onSend,
                  tooltip: 'Odeslat přes Meshtastic',
                  style: IconButton.styleFrom(
                    backgroundColor: rangerGreen,
                    foregroundColor: Colors.white,
                    fixedSize: const Size(48, 48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  icon: const Icon(Icons.send),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TargetPill extends StatelessWidget {
  const _TargetPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: panelGreen,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 17, color: sand),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class MessageCard extends StatelessWidget {
  const MessageCard({required this.message, super.key});

  final MeshMessage message;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  message.internetVoice
                      ? Icons.cloud_outlined
                      : Icons.settings_input_antenna,
                  size: 16,
                  color: message.priority ? signalAmber : sand,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          message.sender,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      if (message.targetLabel != null) ...[
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            message.targetLabel!,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: sand.withValues(alpha: 0.78),
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                      if (message.pending) ...[
                        const SizedBox(width: 8),
                        const Icon(
                          Icons.cloud_off_outlined,
                          size: 14,
                          color: dangerRed,
                        ),
                      ],
                    ],
                  ),
                ),
                Text(
                  message.time,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              message.body,
              style: const TextStyle(fontSize: 14, height: 1.25),
            ),
          ],
        ),
      ),
    );
  }
}

class SystemsPage extends StatelessWidget {
  const SystemsPage({
    required this.meshConnected,
    required this.internetVoiceOnline,
    required this.onMeshChanged,
    required this.onVoiceChanged,
    required this.onBleConnect,
    required this.bleState,
    required this.packetDiagnostics,
    required this.pttState,
    required this.fontScale,
    required this.onFontScaleChanged,
    super.key,
  });

  final bool meshConnected;
  final bool internetVoiceOnline;
  final ValueChanged<bool> onMeshChanged;
  final ValueChanged<bool> onVoiceChanged;
  final VoidCallback onBleConnect;
  final MeshtasticBleState bleState;
  final MeshPacketDiagnostics packetDiagnostics;
  final EncryptedPttState pttState;
  final double fontScale;
  final ValueChanged<double> onFontScaleChanged;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      children: [
        SystemSection(
          title: 'Nastavení',
          icon: Icons.format_size,
          children: [
            Text(
              'Velikost písma',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.86),
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Text(
                  'A',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                ),
                Expanded(
                  child: Slider(
                    value: fontScale,
                    min: 0.85,
                    max: 1.35,
                    divisions: 10,
                    label: '${(fontScale * 100).round()} %',
                    onChanged: onFontScaleChanged,
                  ),
                ),
                const Text(
                  'A',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                ),
              ],
            ),
            MonoLine(
              label: 'Aktuálně',
              value: '${(fontScale * 100).round()} %',
            ),
          ],
        ),
        const SizedBox(height: 10),
        SystemSection(
          title: 'Meshtastic',
          icon: Icons.settings_input_antenna,
          children: [
            SwitchListTile(
              value: meshConnected,
              onChanged: onMeshChanged,
              title: const Text('LILYGO T-Beam 868 MHz přes Bluetooth'),
              subtitle: const Text(
                'Přijímá NodeInfo, Position a textové zprávy',
              ),
            ),
            FilledButton.icon(
              onPressed: onBleConnect,
              style: FilledButton.styleFrom(
                backgroundColor: rangerGreen,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              icon: const Icon(Icons.bluetooth_searching, size: 18),
              label: const Text('Vyhledat T-Beam'),
            ),
            const SizedBox(height: 8),
            MonoLine(label: 'BLE stav', value: _bleStatusLabel(bleState)),
            MonoLine(
              label: 'Pakety',
              value: '${packetDiagnostics.packetCount}',
            ),
            MonoLine(
              label: 'Dekódováno',
              value: '${packetDiagnostics.decodedEventCount} událostí',
            ),
            MonoLine(
              label: 'Poslední událost',
              value: packetDiagnostics.lastDecodedEvent?.label ?? '-',
            ),
            MonoLine(
              label: 'Poslední RX',
              value: _lastPacketLabel(packetDiagnostics),
            ),
            MonoLine(
              label: 'Raw hex',
              value: packetDiagnostics.lastPacketHex.isEmpty
                  ? '-'
                  : packetDiagnostics.lastPacketHex,
            ),
            const MonoLine(
              label: 'Transport',
              value: 'BLE / ToRadio / FromRadio protobuf',
            ),
            const MonoLine(label: 'Role', value: 'CLIENT'),
          ],
        ),
        const SizedBox(height: 10),
        SystemSection(
          title: 'Internet PTT',
          icon: Icons.record_voice_over,
          children: [
            SwitchListTile(
              value: internetVoiceOnline,
              onChanged: onVoiceChanged,
              title: const Text('PTT server online'),
              subtitle: const Text('WebRTC/LiveKit hlas mimo LoRa síť'),
            ),
            const MonoLine(label: 'Kanál', value: 'ALPHA'),
            MonoLine(
              label: 'Šifrování',
              value: pttState.encrypted ? 'AES-GCM 256 aktivní' : 'vypnuto',
            ),
            const MonoLine(label: 'Režim', value: 'Push-to-talk floor control'),
          ],
        ),
        const SizedBox(height: 10),
        const SystemSection(
          title: 'Car Mode',
          icon: Icons.directions_car_filled_outlined,
          children: [
            MonoLine(
              label: 'Android',
              value: 'nativní Kotlin Android Auto modul',
            ),
            MonoLine(label: 'iOS', value: 'nativní Swift CarPlay modul'),
            MonoLine(label: 'UI', value: 'mapa, tým, zprávy, PTT minimum'),
          ],
        ),
        const SizedBox(height: 10),
        const SystemSection(
          title: 'Mapy',
          icon: Icons.map_outlined,
          children: [
            MonoLine(label: 'Podklad', value: 'OpenStreetMap raster tiles'),
            MonoLine(label: 'Cache', value: 'automatická, 512 MB, 30 dní'),
            MonoLine(label: 'Offline', value: 'použije uložené dlaždice'),
          ],
        ),
      ],
    );
  }

  String _bleStatusLabel(MeshtasticBleState state) {
    final device = state.deviceName == null ? '' : ' ${state.deviceName}';
    return switch (state.status) {
      MeshtasticBleStatus.idle => 'čeká',
      MeshtasticBleStatus.scanning => 'skenuje',
      MeshtasticBleStatus.connecting => 'připojuje$device',
      MeshtasticBleStatus.connected => 'připojeno$device',
      MeshtasticBleStatus.disconnected => 'odpojeno',
      MeshtasticBleStatus.error => 'chyba ${state.lastError ?? ''}',
    };
  }

  String _lastPacketLabel(MeshPacketDiagnostics diagnostics) {
    final lastPacketAt = diagnostics.lastPacketAt;
    if (lastPacketAt == null) {
      return '-';
    }
    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(lastPacketAt.hour)}:${two(lastPacketAt.minute)}:${two(lastPacketAt.second)} / ${diagnostics.lastPacketSize} B';
  }
}

class PttBar extends StatelessWidget {
  const PttBar({
    required this.active,
    required this.enabled,
    required this.onChanged,
    required this.channel,
    required this.userName,
    required this.encrypted,
    this.compact = false,
    super.key,
  });

  final bool active;
  final bool enabled;
  final ValueChanged<bool> onChanged;
  final String channel;
  final String userName;
  final bool encrypted;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(12, compact ? 6 : 8, 12, compact ? 8 : 10),
      color: const Color(0xFF10130D),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  userName,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: signalAmber,
                    fontSize: compact ? 15 : 17,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  enabled
                      ? 'PTT $channel | ${active ? 'VYSILANI' : 'PRIPRAVENO'} | ${encrypted ? 'AES-GCM' : 'NEŠIFROVÁNO'}'
                      : 'PTT SERVER OFFLINE',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: enabled ? Colors.white : dangerRed,
                    fontSize: compact ? 11 : 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTapDown: enabled ? (_) => onChanged(true) : null,
            onTapUp: enabled ? (_) => onChanged(false) : null,
            onTapCancel: enabled ? () => onChanged(false) : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              height: compact ? 44 : 54,
              width: compact ? 132 : 150,
              decoration: BoxDecoration(
                color: !enabled
                    ? Colors.grey.shade800
                    : (active ? signalAmber : rangerGreen),
                borderRadius: BorderRadius.circular(8),
                boxShadow: active
                    ? [
                        BoxShadow(
                          color: signalAmber.withValues(alpha: 0.35),
                          blurRadius: 18,
                          spreadRadius: 2,
                        ),
                      ]
                    : null,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    active ? Icons.mic : Icons.mic_none,
                    color: active ? Colors.black : Colors.white,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    active ? 'TALK' : 'PTT',
                    style: TextStyle(
                      color: active ? Colors.black : Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class MetricTile extends StatelessWidget {
  const MetricTile({
    required this.label,
    required this.value,
    required this.icon,
    this.compact = false,
    super.key,
  });

  final String label;
  final String value;
  final IconData icon;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 10 : 12,
          vertical: compact ? 8 : 10,
        ),
        child: Row(
          children: [
            Icon(icon, color: sand, size: compact ? 18 : 20),
            SizedBox(width: compact ? 8 : 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.white.withValues(alpha: 0.62),
                    ),
                  ),
                  Text(
                    value,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: compact ? 14 : 16,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class BatteryBadge extends StatelessWidget {
  const BatteryBadge({required this.percent, super.key});

  final int percent;

  @override
  Widget build(BuildContext context) {
    final color = percent < 25 ? dangerRed : sand;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Icon(Icons.battery_5_bar, size: 15, color: color),
          const SizedBox(width: 4),
          Text(
            '$percent%',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class QuickActionButton extends StatelessWidget {
  const QuickActionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.danger = false,
    super.key,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? dangerRed : rangerGreen;
    return FilledButton.icon(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(46),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      icon: Icon(icon, size: 18),
      label: Text(label, overflow: TextOverflow.ellipsis),
    );
  }
}

class SystemSection extends StatelessWidget {
  const SystemSection({
    required this.title,
    required this.icon,
    required this.children,
    super.key,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: sand),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const Divider(height: 22),
            ...children,
          ],
        ),
      ),
    );
  }
}

class MonoLine extends StatelessWidget {
  const MonoLine({
    required this.label,
    required this.value,
    this.labelWidth = 82,
    this.allowWrap = false,
    super.key,
  });

  final String label;
  final String value;
  final double labelWidth;
  final bool allowWrap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: labelWidth,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Colors.white.withValues(alpha: 0.55),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              overflow: allowWrap
                  ? TextOverflow.visible
                  : TextOverflow.ellipsis,
              softWrap: allowWrap,
              maxLines: allowWrap ? 2 : 1,
              style: const TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class MeshNode {
  const MeshNode({
    required this.nodeNum,
    required this.callSign,
    required this.latitude,
    required this.longitude,
    required this.altitudeM,
    required this.mgrs,
    required this.batteryPercent,
    required this.lastSeenMinutes,
    required this.distanceKm,
    required this.bearingDeg,
    required this.mapOffset,
    this.isSelf = false,
  });

  final int nodeNum;
  final String callSign;
  final double latitude;
  final double longitude;
  final int altitudeM;
  final String mgrs;
  final int batteryPercent;
  final int lastSeenMinutes;
  final double distanceKm;
  final double bearingDeg;
  final Offset mapOffset;
  final bool isSelf;

  LatLng get latLng => LatLng(latitude, longitude);

  Map<String, dynamic> toJson() {
    return {
      'nodeNum': nodeNum,
      'callSign': callSign,
      'latitude': latitude,
      'longitude': longitude,
      'altitudeM': altitudeM,
      'mgrs': mgrs,
      'batteryPercent': batteryPercent,
      'lastSeenMinutes': lastSeenMinutes,
      'distanceKm': distanceKm,
      'bearingDeg': bearingDeg,
      'mapOffsetX': mapOffset.dx,
      'mapOffsetY': mapOffset.dy,
      'isSelf': isSelf,
    };
  }

  static MeshNode fromJson(Map<String, dynamic> json) {
    return MeshNode(
      nodeNum: (json['nodeNum'] as num).toInt(),
      callSign: json['callSign']?.toString() ?? 'UNKNOWN',
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      altitudeM: (json['altitudeM'] as num?)?.toInt() ?? 0,
      mgrs: json['mgrs']?.toString() ?? '',
      batteryPercent: (json['batteryPercent'] as num?)?.toInt() ?? 100,
      lastSeenMinutes: (json['lastSeenMinutes'] as num?)?.toInt() ?? 0,
      distanceKm: (json['distanceKm'] as num?)?.toDouble() ?? 0,
      bearingDeg: (json['bearingDeg'] as num?)?.toDouble() ?? 0,
      mapOffset: Offset(
        (json['mapOffsetX'] as num?)?.toDouble() ?? 0,
        (json['mapOffsetY'] as num?)?.toDouble() ?? 0,
      ),
      isSelf: json['isSelf'] == true,
    );
  }

  MeshNode copyWith({
    int? nodeNum,
    String? callSign,
    double? latitude,
    double? longitude,
    int? altitudeM,
    String? mgrs,
    int? batteryPercent,
    int? lastSeenMinutes,
    double? distanceKm,
    double? bearingDeg,
    Offset? mapOffset,
    bool? isSelf,
  }) {
    return MeshNode(
      nodeNum: nodeNum ?? this.nodeNum,
      callSign: callSign ?? this.callSign,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      altitudeM: altitudeM ?? this.altitudeM,
      mgrs: mgrs ?? this.mgrs,
      batteryPercent: batteryPercent ?? this.batteryPercent,
      lastSeenMinutes: lastSeenMinutes ?? this.lastSeenMinutes,
      distanceKm: distanceKm ?? this.distanceKm,
      bearingDeg: bearingDeg ?? this.bearingDeg,
      mapOffset: mapOffset ?? this.mapOffset,
      isSelf: isSelf ?? this.isSelf,
    );
  }

  static const demoNodes = [
    MeshNode(
      nodeNum: 0xA1100001,
      callSign: 'RAVEN-1',
      latitude: 50.087451,
      longitude: 14.420671,
      altitudeM: 241,
      mgrs: '33U VR 58470 48210',
      batteryPercent: 88,
      lastSeenMinutes: 0,
      distanceKm: 0,
      bearingDeg: 0,
      mapOffset: Offset.zero,
      isSelf: true,
    ),
    MeshNode(
      nodeNum: 0xA1100002,
      callSign: 'RAVEN-2',
      latitude: 50.094220,
      longitude: 14.407812,
      altitudeM: 252,
      mgrs: '33U VR 57541 48958',
      batteryPercent: 76,
      lastSeenMinutes: 1,
      distanceKm: 1.2,
      bearingDeg: 313,
      mapOffset: Offset(-0.42, -0.31),
    ),
    MeshNode(
      nodeNum: 0xA1100003,
      callSign: 'SCOUT-3',
      latitude: 50.081312,
      longitude: 14.438220,
      altitudeM: 219,
      mgrs: '33U VR 59728 47517',
      batteryPercent: 61,
      lastSeenMinutes: 3,
      distanceKm: 1.5,
      bearingDeg: 119,
      mapOffset: Offset(0.47, 0.34),
    ),
    MeshNode(
      nodeNum: 0xA1100004,
      callSign: 'MED-4',
      latitude: 50.079502,
      longitude: 14.411871,
      altitudeM: 236,
      mgrs: '33U VR 57821 47302',
      batteryPercent: 22,
      lastSeenMinutes: 8,
      distanceKm: 1.1,
      bearingDeg: 221,
      mapOffset: Offset(-0.26, 0.41),
    ),
  ];
}

class TacticalWaypoint {
  const TacticalWaypoint({
    required this.code,
    required this.type,
    required this.latitude,
    required this.longitude,
    required this.mgrs,
    required this.note,
    this.priority = false,
  });

  final String code;
  final TacticalWaypointType type;
  final double latitude;
  final double longitude;
  final String mgrs;
  final String note;
  final bool priority;

  LatLng get latLng => LatLng(latitude, longitude);

  IconData get icon {
    return switch (type) {
      TacticalWaypointType.rally => Icons.flag_outlined,
      TacticalWaypointType.medevac => Icons.medical_services_outlined,
      TacticalWaypointType.danger => Icons.warning_amber_outlined,
      TacticalWaypointType.observation => Icons.visibility_outlined,
      TacticalWaypointType.supply => Icons.inventory_2_outlined,
    };
  }

  String get typeLabel {
    return switch (type) {
      TacticalWaypointType.rally => 'RALLY',
      TacticalWaypointType.medevac => 'MEDEVAC',
      TacticalWaypointType.danger => 'DANGER',
      TacticalWaypointType.observation => 'OBS',
      TacticalWaypointType.supply => 'SUPPLY',
    };
  }

  static const demoWaypoints = [
    TacticalWaypoint(
      code: 'RALLY-1',
      type: TacticalWaypointType.rally,
      latitude: 50.086138,
      longitude: 14.414208,
      mgrs: '33U VR 58009 48063',
      note: 'primarni shromazdiste',
    ),
    TacticalWaypoint(
      code: 'MED-POINT',
      type: TacticalWaypointType.medevac,
      latitude: 50.083846,
      longitude: 14.427594,
      mgrs: '33U VR 58967 47810',
      note: 'vyzvednuti zranenych',
      priority: true,
    ),
    TacticalWaypoint(
      code: 'OBS-2',
      type: TacticalWaypointType.observation,
      latitude: 50.091922,
      longitude: 14.432875,
      mgrs: '33U VR 59347 48708',
      note: 'pozorovaci bod sever',
    ),
  ];
}

enum TacticalWaypointType { rally, medevac, danger, observation, supply }

class MeshMessage {
  const MeshMessage({
    required this.sender,
    required this.body,
    required this.time,
    required this.groupId,
    this.targetLabel,
    this.pending = false,
    this.priority = false,
    this.internetVoice = false,
  });

  final String sender;
  final String body;
  final String time;
  final String groupId;
  final String? targetLabel;
  final bool pending;
  final bool priority;
  final bool internetVoice;

  Map<String, dynamic> toJson() {
    return {
      'sender': sender,
      'body': body,
      'time': time,
      'groupId': groupId,
      'targetLabel': targetLabel,
      'pending': pending,
      'priority': priority,
      'internetVoice': internetVoice,
    };
  }

  static MeshMessage fromJson(Map<String, dynamic> json) {
    return MeshMessage(
      sender: json['sender']?.toString() ?? 'UNKNOWN',
      body: json['body']?.toString() ?? '',
      time: json['time']?.toString() ?? '--:--',
      groupId: json['groupId']?.toString() ?? 'alpha',
      targetLabel: json['targetLabel']?.toString(),
      pending: json['pending'] == true,
      priority: json['priority'] == true,
      internetVoice: json['internetVoice'] == true,
    );
  }

  static const demoMessages = [
    MeshMessage(
      sender: 'RAVEN-2',
      body: 'Na pozici. Vidim trasu k bodu BRAVO.',
      time: '14:22',
      groupId: 'alpha',
      priority: false,
    ),
    MeshMessage(
      sender: 'SCOUT-3',
      body: 'Posilam novou pozici pres Meshtastic.',
      time: '14:19',
      groupId: 'alpha',
    ),
    MeshMessage(
      sender: 'PTT SERVER',
      body: 'ALPHA voice channel online. Floor control aktivni.',
      time: '14:18',
      groupId: 'alpha',
      internetVoice: true,
    ),
    MeshMessage(
      sender: 'MED-4',
      body: 'Baterie nizka, zustavam u vozidla.',
      time: '14:14',
      groupId: 'med',
      priority: true,
    ),
    MeshMessage(
      sender: 'COMMAND',
      body: 'BRAVO zustava jako zalozni presunovy kanal.',
      time: '14:11',
      groupId: 'bravo',
    ),
    MeshMessage(
      sender: 'HQ',
      body: 'Kontrola spojeni a prihlaseni posadek.',
      time: '14:05',
      groupId: 'command',
    ),
  ];
}

class CommunicationGroup {
  const CommunicationGroup({
    required this.id,
    required this.name,
    required this.transportLabel,
    required this.icon,
    required this.channelIndex,
    this.encrypted = true,
  });

  final String id;
  final String name;
  final String transportLabel;
  final IconData icon;
  final int channelIndex;
  final bool encrypted;

  static const demoGroups = [
    CommunicationGroup(
      id: 'alpha',
      name: 'ALPHA',
      transportLabel: 'Meshtastic + PTT',
      icon: Icons.radio,
      channelIndex: 0,
    ),
    CommunicationGroup(
      id: 'bravo',
      name: 'BRAVO',
      transportLabel: 'Meshtastic',
      icon: Icons.settings_input_antenna,
      channelIndex: 1,
    ),
    CommunicationGroup(
      id: 'med',
      name: 'MED',
      transportLabel: 'prioritní',
      icon: Icons.medical_services_outlined,
      channelIndex: 2,
    ),
    CommunicationGroup(
      id: 'command',
      name: 'COMMAND',
      transportLabel: 'šifrované',
      icon: Icons.admin_panel_settings_outlined,
      channelIndex: 3,
    ),
  ];
}

class MeshMessageDraft {
  const MeshMessageDraft({
    required this.text,
    required this.groupId,
    this.directNode,
    this.priority = false,
  });

  final String text;
  final String groupId;
  final MeshNode? directNode;
  final bool priority;
}

double radians(double degrees) => degrees * math.pi / 180;
