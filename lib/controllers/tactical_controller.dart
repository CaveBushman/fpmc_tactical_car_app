import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../models/mesh_node.dart';
import '../models/messaging.dart';
import '../models/navigation.dart';
import '../services/auth_service.dart';
import '../services/encrypted_ptt_service.dart';
import '../services/location_service.dart';
import '../services/mesh_packet_repository.dart';
import '../services/meshtastic_ble_service.dart';
import '../services/meshtastic_message_encoder.dart';
import '../services/meshtastic_packet_decoder.dart';
import '../services/ptt_access_service.dart';
import '../services/tactical_state_store.dart';

/// Owns the operational state (session, nodes, messages, radio, GPS, PTT)
/// and the services behind it. Widgets read it and call its methods; they
/// hold only presentation state.
class TacticalController extends ChangeNotifier {
  TacticalController({
    AuthService? authService,
    LocationService? locationService,
    MeshPacketRepository? meshPacketRepository,
    MeshtasticBleService? meshtasticBleService,
    TacticalStateStore? stateStore,
    Duration agingTick = const Duration(seconds: 15),
  }) : _authService = authService ?? AuthService(),
       _locationService = locationService ?? GeolocatorLocationService(),
       _meshPacketRepository = meshPacketRepository ?? MeshPacketRepository(),
       _meshtasticBleService = meshtasticBleService ?? MeshtasticBleService(),
       _stateStore = stateStore ?? const TacticalStateStore() {
    _locationStateSubscription = _locationService.stateStream.listen((state) {
      _locationState = state;
      _notify();
    });
    _locationFixSubscription = _locationService.fixes.listen(_applySelfFix);
    _bleStateSubscription = _meshtasticBleService.stateStream.listen((state) {
      _bleState = state;
      _notify();
    });
    _pttStateSubscription = _pttService.stateStream.listen((state) {
      _pttState = state;
      _notify();
    });
    _blePacketSubscription = _meshtasticBleService.packets.listen(
      _meshPacketRepository.ingest,
    );
    _packetDiagnosticsSubscription = _meshPacketRepository.diagnosticsStream
        .listen((diagnostics) {
          _packetDiagnostics = diagnostics;
          _notify();
        });
    _meshEventsSubscription = _meshPacketRepository.eventsStream.listen(
      _applyDecodedMeshEvents,
    );
    // Link status is derived from wall clock; re-evaluate it periodically
    // instead of rebuilding the whole UI every second.
    _agingTimer = Timer.periodic(agingTick, (_) {
      if (_session != null) {
        _notify();
      }
    });
  }

  final AuthService _authService;
  final LocationService _locationService;
  final MeshPacketRepository _meshPacketRepository;
  final MeshtasticBleService _meshtasticBleService;
  final TacticalStateStore _stateStore;
  final PttAccessService _pttAccessService = const PttAccessService();
  final MeshtasticMessageEncoder _messageEncoder =
      const MeshtasticMessageEncoder();
  final EncryptedPttService _pttService = EncryptedPttService(channel: 'ALPHA');
  final math.Random _packetIdRandom = math.Random.secure();
  final StreamController<String> _noticeController =
      StreamController.broadcast();

  late final StreamSubscription<LocationState> _locationStateSubscription;
  late final StreamSubscription<LocationFix> _locationFixSubscription;
  late final StreamSubscription<MeshtasticBleState> _bleStateSubscription;
  late final StreamSubscription<MeshtasticBlePacket> _blePacketSubscription;
  late final StreamSubscription<MeshPacketDiagnostics>
  _packetDiagnosticsSubscription;
  late final StreamSubscription<List<DecodedMeshEvent>> _meshEventsSubscription;
  late final StreamSubscription<EncryptedPttState> _pttStateSubscription;
  late final Timer _agingTimer;

  bool _disposed = false;
  AuthSession? _session;
  int _selectedGroupIndex = 0;
  bool _pttActive = false;
  bool _internetVoiceOnline = true;
  double _fontScale = 1.0;
  DateTime? _lastLocationPersistAt;
  LocationState _locationState = LocationState.idle;
  MeshtasticBleState _bleState = MeshtasticBleState.idle;
  MeshPacketDiagnostics _packetDiagnostics = MeshPacketDiagnostics.empty;
  EncryptedPttState _pttState = const EncryptedPttState(
    status: EncryptedPttStatus.ready,
    channel: 'ALPHA',
    encrypted: true,
  );

  final List<MeshNode> _nodes = MeshNode.demoNodes(DateTime.now());
  final List<MeshMessage> _messages = MeshMessage.demoMessages(DateTime.now());
  final List<CommunicationGroup> _groups = CommunicationGroup.demoGroups;
  final List<TacticalWaypoint> _waypoints = [...TacticalWaypoint.demoWaypoints];

  /// User-facing notices (shown as snack bars).
  Stream<String> get notices => _noticeController.stream;

  AuthSession? get session => _session;
  List<MeshNode> get nodes => List.unmodifiable(_nodes);
  List<MeshNode> get peers => _nodes.where((node) => !node.isSelf).toList();
  MeshNode get selfNode => _nodes.firstWhere((node) => node.isSelf);
  List<MeshMessage> get messages => List.unmodifiable(_messages);
  List<TacticalWaypoint> get waypoints => List.unmodifiable(_waypoints);
  bool get pttActive => _pttActive;
  bool get internetVoiceOnline => _internetVoiceOnline;
  bool get meshConnected => _bleState.status == MeshtasticBleStatus.connected;
  double get fontScale => _fontScale;
  LocationState get locationState => _locationState;
  MeshtasticBleState get bleState => _bleState;
  MeshPacketDiagnostics get packetDiagnostics => _packetDiagnostics;
  EncryptedPttState get pttState => _pttState;

  List<CommunicationGroup> get allowedGroups {
    final session = _session;
    if (session == null) {
      return const [];
    }
    return _groups
        .where((group) => session.allowedGroupIds.contains(group.id))
        .toList();
  }

  int get selectedGroupIndex {
    final count = allowedGroups.length;
    return _selectedGroupIndex < count ? _selectedGroupIndex : 0;
  }

  CommunicationGroup get selectedGroup => allowedGroups[selectedGroupIndex];

  @override
  void dispose() {
    _disposed = true;
    _agingTimer.cancel();
    unawaited(_bleStateSubscription.cancel());
    unawaited(_blePacketSubscription.cancel());
    unawaited(_packetDiagnosticsSubscription.cancel());
    unawaited(_meshEventsSubscription.cancel());
    unawaited(_pttStateSubscription.cancel());
    unawaited(_locationStateSubscription.cancel());
    unawaited(_locationFixSubscription.cancel());
    unawaited(_locationService.dispose());
    unawaited(_meshtasticBleService.dispose());
    unawaited(_meshPacketRepository.dispose());
    unawaited(_pttService.dispose());
    unawaited(_noticeController.close());
    super.dispose();
  }

  // --- Session -------------------------------------------------------------

  /// Returns an error message, or null on success.
  Future<String?> login(String userName, String password) async {
    final result = await _authService.login(
      userName: userName,
      password: password,
    );
    if (!result.ok) {
      return result.errorMessage;
    }
    final session = result.session!;
    _session = session;
    _selectedGroupIndex = 0;
    _notify();
    unawaited(_locationService.start());
    unawaited(_restorePersistedState(session.userName));
    _syncPttChannel(session, selectedGroup);
    return null;
  }

  /// Ends the session and wipes everything stored on the device.
  Future<void> logout() async {
    // Drop the session first so no in-flight persist can rewrite the store.
    _session = null;
    _selectedGroupIndex = 0;
    _notify();
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
    _replaceNodes(MeshNode.demoNodes(DateTime.now()));
    _messages
      ..clear()
      ..addAll(MeshMessage.demoMessages(DateTime.now()));
    _waypoints
      ..clear()
      ..addAll(TacticalWaypoint.demoWaypoints);
    _notify();
  }

  // --- Settings / devices --------------------------------------------------

  void setFontScale(double value) {
    _fontScale = value;
    _notify();
  }

  void setInternetVoiceOnline(bool value) {
    _internetVoiceOnline = value;
    _notify();
  }

  Future<void> connectRadio() => _meshtasticBleService.startAutoConnect();

  Future<void> startLocation() => _locationService.start();

  Future<void> openLocationSettings() => _locationService.openSettings();

  // --- PTT -----------------------------------------------------------------

  void setPttActive(bool value) {
    if (value) {
      _pttService.beginTransmit();
    } else {
      _pttService.endTransmit();
    }
    _pttActive = value;
    _notify();
  }

  void selectGroup(int index) {
    final session = _session;
    if (session == null) {
      return;
    }
    _selectedGroupIndex = index;
    _notify();
    _syncPttChannel(session, selectedGroup);
  }

  void _syncPttChannel(AuthSession session, CommunicationGroup group) {
    final access = _pttAccessService.authorize(
      session: session,
      groupId: group.id,
    );
    _pttService.switchChannel(
      channel: access.channel,
      keyBytes: access.keyBytes,
    );
  }

  // --- Own position ----------------------------------------------------------

  void _applySelfFix(LocationFix fix) {
    final selfIndex = _nodes.indexWhere((node) => node.isSelf);
    if (selfIndex == -1) {
      return;
    }
    _nodes[selfIndex] = _nodes[selfIndex].copyWith(
      latitude: fix.latitude,
      longitude: fix.longitude,
      altitudeM: fix.altitudeM.round(),
      lastSeenAt: fix.timestamp,
    );
    _replaceNodes(MeshNode.relativeToSelf(_nodes));
    _notify();

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

  // --- Incoming mesh traffic -------------------------------------------------

  void _applyDecodedMeshEvents(List<DecodedMeshEvent> events) {
    var changed = false;
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
        case DecodedMeshEventType.telemetry:
          changed = _applyTelemetry(event) || changed;
        case DecodedMeshEventType.waypoint:
          changed = _applyMeshWaypoint(event) || changed;
        case DecodedMeshEventType.routing:
          changed = _applyRoutingResult(event) || changed;
        case DecodedMeshEventType.encrypted:
        case DecodedMeshEventType.unknown:
          break;
      }
    }
    if (changed) {
      _notify();
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
    final self = selfNode;
    if (nodeNum == self.nodeNum) {
      // Our own NodeInfo from the radio carries the configured callsign and
      // the T-Beam battery; position stays driven by the phone GPS.
      final name = _eventCallSign(event) ?? self.callSign;
      final battery = event.batteryLevel ?? self.batteryPercent;
      if (name == self.callSign && battery == self.batteryPercent) {
        return false;
      }
      _nodes[_nodes.indexOf(self)] = self.copyWith(
        callSign: name,
        batteryPercent: battery,
      );
      return true;
    }

    final existingIndex = _nodes.indexWhere((node) => node.nodeNum == nodeNum);
    final existing = existingIndex == -1 ? null : _nodes[existingIndex];
    final latitude = event.latitude ?? existing?.latitude;
    final longitude = event.longitude ?? existing?.longitude;
    if (latitude == null || longitude == null) {
      return false;
    }

    final updated = MeshNode(
      nodeNum: nodeNum,
      callSign:
          _eventCallSign(event) ?? existing?.callSign ?? _nodeHex(nodeNum),
      latitude: latitude,
      longitude: longitude,
      altitudeM: event.altitude ?? existing?.altitudeM ?? 0,
      batteryPercent: event.batteryLevel ?? existing?.batteryPercent,
      lastSeenAt: _latest(
        event.heardAt ?? DateTime.now(),
        existing?.lastSeenAt,
      ),
    ).relativeTo(self);

    if (existingIndex == -1) {
      _nodes.add(updated);
    } else {
      _nodes[existingIndex] = updated;
    }
    return true;
  }

  /// Battery from TELEMETRY_APP; also counts as the node being heard.
  bool _applyTelemetry(DecodedMeshEvent event) {
    final nodeNum = event.from;
    final battery = event.batteryLevel;
    if (nodeNum == null || battery == null) {
      return false;
    }
    final index = _nodes.indexWhere((node) => node.nodeNum == nodeNum);
    if (index == -1) {
      // Unknown node without a position cannot be placed yet.
      return false;
    }
    final node = _nodes[index];
    _nodes[index] = node.copyWith(
      batteryPercent: battery,
      lastSeenAt: node.isSelf
          ? null
          : _latest(event.heardAt ?? DateTime.now(), node.lastSeenAt),
    );
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

    // Unknown channel indexes land in the primary channel group.
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
    final sharedWaypoint = TacticalWaypoint.parseShareText(
      text,
      sharedBy: sender,
      receivedAt: DateTime.now(),
    );
    if (sharedWaypoint != null) {
      _upsertWaypoint(sharedWaypoint);
    }
    _messages.insert(
      0,
      MeshMessage(
        sender: sender,
        body: text,
        sentAt: event.heardAt ?? DateTime.now(),
        groupId: group.id,
        targetLabel: target,
        packetId: packetId,
        fromNode: event.from,
      ),
    );
    return true;
  }

  bool _applyRoutingResult(DecodedMeshEvent event) {
    final requestId = event.requestId;
    if (requestId == null || requestId == 0) {
      return false;
    }
    final index = _outgoingIndex(requestId);
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

  // --- Outgoing mesh traffic -------------------------------------------------

  Future<void> sendMeshText(MeshMessageDraft draft) async {
    final group = allowedGroups.firstWhere((item) => item.id == draft.groupId);
    final directNode = draft.directNode;
    final self = selfNode;
    final outgoingMessage = MeshMessage(
      sender: self.callSign,
      body: draft.text,
      sentAt: DateTime.now(),
      groupId: draft.groupId,
      targetLabel: directNode == null
          ? group.name
          : 'DM ${directNode.callSign}',
      delivery: MessageDelivery.sending,
      priority: draft.priority,
      packetId: _newPacketId(),
      fromNode: self.nodeNum,
      toNode: directNode?.nodeNum,
    );
    _messages.insert(0, outgoingMessage);
    _notify();
    await _transmit(outgoingMessage);
  }

  Future<void> retryMessage(MeshMessage message) async {
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
    if (_replaceOutgoing(packetId, (_) => retry)) {
      await _transmit(retry);
    }
  }

  /// Adds a waypoint created on this device; returns it with a unique code.
  TacticalWaypoint addWaypoint({
    required TacticalWaypointType type,
    required double latitude,
    required double longitude,
    String? code,
    String note = '',
  }) {
    final waypoint = TacticalWaypoint(
      code: _uniqueWaypointCode(code, type),
      type: type,
      latitude: latitude,
      longitude: longitude,
      note: note.trim(),
      priority:
          type == TacticalWaypointType.medevac ||
          type == TacticalWaypointType.danger,
      createdAt: DateTime.now(),
    );
    _waypoints.add(waypoint);
    _notify();
    unawaited(_persistState());
    return waypoint;
  }

  void removeWaypoint(TacticalWaypoint waypoint) {
    final removed = _waypoints.remove(waypoint);
    if (removed) {
      _notify();
      unawaited(_persistState());
    }
  }

  String _uniqueWaypointCode(String? requested, TacticalWaypointType type) {
    final base = (requested ?? '').trim().toUpperCase().replaceAll(
      RegExp(r'\s+'),
      '-',
    );
    bool taken(String code) => _waypoints.any((w) => w.code == code);
    if (base.isNotEmpty && !taken(base)) {
      return base;
    }
    final prefix = base.isNotEmpty ? base : type.label;
    for (var n = 1; ; n++) {
      final candidate = '$prefix-$n';
      if (!taken(candidate)) {
        return candidate;
      }
    }
  }

  /// Same code (text share) or same Meshtastic id replaces the old point.
  void _upsertWaypoint(TacticalWaypoint waypoint) {
    final index = _waypoints.indexWhere(
      (existing) =>
          existing.code == waypoint.code ||
          (waypoint.meshWaypointId != null &&
              existing.meshWaypointId == waypoint.meshWaypointId),
    );
    if (index == -1) {
      _waypoints.add(waypoint);
    } else {
      _waypoints[index] = waypoint;
    }
  }

  bool _applyMeshWaypoint(DecodedMeshEvent event) {
    final id = event.waypointId;
    if (id == null) {
      return false;
    }
    final expire = event.waypointExpire ?? 0;
    final nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (expire != 0 && expire <= nowSeconds) {
      final before = _waypoints.length;
      _waypoints.removeWhere((w) => w.meshWaypointId == id);
      return _waypoints.length != before;
    }
    final latitude = event.latitude;
    final longitude = event.longitude;
    if (latitude == null || longitude == null) {
      return false;
    }
    final name = event.waypointName?.trim() ?? '';
    final description = event.waypointDescription?.trim() ?? '';
    final type =
        TacticalWaypoint.typeFromLabel(name.split(RegExp(r'[\s-]')).first) ??
        TacticalWaypointType.observation;
    _upsertWaypoint(
      TacticalWaypoint(
        code: name.isEmpty
            ? 'WP-${id.toRadixString(16).toUpperCase()}'
            : name.toUpperCase().replaceAll(RegExp(r'\s+'), '-'),
        type: type,
        latitude: latitude,
        longitude: longitude,
        note: description,
        priority:
            type == TacticalWaypointType.medevac ||
            type == TacticalWaypointType.danger,
        sharedBy: _nodeCallSign(event.from) ?? _nodeHex(event.from),
        createdAt: DateTime.now(),
        meshWaypointId: id,
      ),
    );
    return true;
  }

  Future<void> shareWaypoint(TacticalWaypoint waypoint) {
    return sendMeshText(
      MeshMessageDraft(
        text: waypoint.shareText,
        groupId: selectedGroup.id,
        priority: waypoint.priority,
      ),
    );
  }

  Future<void> sendCheckIn(MeshNode node) {
    final text =
        'CHECK-IN | ${node.callSign} | LAST ${node.lastSeenMinutes} min | MGRS ${node.mgrs} | STATUS ${node.linkStatus.label}';
    return sendMeshText(
      MeshMessageDraft(
        text: text,
        groupId: selectedGroup.id,
        directNode: node,
        priority: node.linkStatus != MeshNodeLinkStatus.ok,
      ),
    );
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
    } catch (_) {
      delivery = MessageDelivery.notSent;
      _notice('T-Beam není připojen: zprávu lze odeslat znovu ze seznamu.');
    }

    _replaceOutgoing(
      packetId,
      (current) => current.delivery == MessageDelivery.sending
          ? current.copyWith(delivery: delivery)
          : current,
    );
  }

  int _outgoingIndex(int packetId) {
    return _messages.indexWhere(
      (message) =>
          message.packetId == packetId &&
          message.delivery != MessageDelivery.received,
    );
  }

  /// Replaces our own outgoing message carrying [packetId]; returns false
  /// when it is no longer in the list.
  bool _replaceOutgoing(
    int packetId,
    MeshMessage Function(MeshMessage current) update,
  ) {
    final index = _outgoingIndex(packetId);
    if (index == -1) {
      return false;
    }
    _messages[index] = update(_messages[index]);
    _notify();
    unawaited(_persistState());
    return true;
  }

  int _newPacketId() => _packetIdRandom.nextInt(0x7FFFFFFF) + 1;

  // --- Persistence -----------------------------------------------------------

  Future<void> _restorePersistedState(String userName) async {
    try {
      final snapshot = await _stateStore.load();
      if (_disposed || snapshot == null) {
        return;
      }
      // A snapshot left behind by another user (app killed without logout)
      // must not leak into this session.
      final owner = snapshot.owner;
      if (owner != null && owner != userName) {
        await _stateStore.clear();
        return;
      }

      final selfNodeNum = selfNode.nodeNum;
      final restoredNodes = snapshot.nodes
          .map(MeshNode.fromJson)
          .where((node) => node.isSelf || node.nodeNum != selfNodeNum)
          .toList();
      final restoredMessages = snapshot.messages
          .map(MeshMessage.fromJson)
          .toList();
      final restoredWaypoints = snapshot.waypoints
          ?.map(TacticalWaypoint.fromJson)
          .toList();
      if (restoredNodes.isEmpty &&
          restoredMessages.isEmpty &&
          restoredWaypoints == null) {
        return;
      }

      if (restoredNodes.any((node) => node.isSelf)) {
        _replaceNodes(MeshNode.relativeToSelf(restoredNodes));
      }
      if (restoredMessages.isNotEmpty) {
        _messages
          ..clear()
          ..addAll(restoredMessages);
      }
      // An empty list is a valid state (all points deleted); only legacy
      // snapshots without the key keep the defaults.
      if (restoredWaypoints != null) {
        _waypoints
          ..clear()
          ..addAll(restoredWaypoints);
      }
      _notify();
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
        waypoints: [for (final waypoint in _waypoints) waypoint.toJson()],
        owner: session.userName,
      );
    } catch (_) {
      // Persistence is best effort; the live session keeps working.
    }
  }

  // --- Helpers -----------------------------------------------------------------

  void _replaceNodes(List<MeshNode> nodes) {
    _nodes
      ..clear()
      ..addAll(nodes);
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  void _notice(String message) {
    if (!_noticeController.isClosed) {
      _noticeController.add(message);
    }
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
}
