import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../models/geo.dart' as geo;
import '../models/mesh_node.dart';
import '../models/messaging.dart';
import '../models/navigation.dart';
import '../models/track.dart';
import '../models/reports.dart';
import '../models/sos.dart';
import '../services/auth_service.dart';
import '../services/backend_client.dart';
import '../services/native_bridges.dart';
import '../services/settings_store.dart';
import '../services/ptt/livekit_voice_transport.dart';
import '../services/ptt/voice_transport.dart';
import 'ptt_controller.dart';
import '../services/location_service.dart';
import '../services/mesh_packet_repository.dart';
import '../services/mission_export.dart';
import '../services/mesh_radio.dart';
import '../services/meshtastic_ble_service.dart';
import '../services/meshtastic_message_encoder.dart';
import '../services/meshtastic_packet_decoder.dart';
import '../services/tactical_state_store.dart';

/// Owns the operational state (session, nodes, messages, radio, GPS, PTT)
/// and the services behind it. Widgets read it and call its methods; they
/// hold only presentation state.
class TacticalController extends ChangeNotifier {
  TacticalController({
    AuthService? authService,
    LocationService? locationService,
    MeshPacketRepository? meshPacketRepository,
    MeshRadio? meshtasticBleService,
    TacticalStateStore? stateStore,
    BackendClient? backend,
    VoiceTransport Function()? voiceTransportFactory,
    NativePttBridge? nativePtt,
    CarBridge? carBridge,
    this.settings = const SettingsStore(),
    this.minSessionRefreshDelay = const Duration(seconds: 30),
    this.sosRepeat = const Duration(minutes: 1),
    MissionSharer? missionSharer,
    Duration agingTick = const Duration(seconds: 15),
  }) : _backend = backend,
       _nativePtt = nativePtt ?? NativePttBridge.platform(),
       _carBridge = carBridge ?? CarBridge.platform(),
       _missionSharer = missionSharer ?? MissionSharer.system(),
       _authService =
           authService ??
           (backend == null ? AuthService() : RemoteAuthService(backend)),
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
    _ptt = PttController(
      joiner: backend == null ? null : _joinPtt,
      transportFactory: voiceTransportFactory ?? LiveKitVoiceTransport.new,
    )..addListener(_onPttChanged);
    _nativeButtonSubscription = _nativePtt.buttons.listen(_onNativeButton);
    _nativeErrorSubscription = _nativePtt.errors.listen(
      (error) => _notice('PTT na pozadí nelze spustit ($error).'),
    );
    _carReplySubscription = _carBridge.replies.listen(_onCarReply);
    _roomDataSubscription = _ptt.roomData.listen(_onRoomData);
    unawaited(_loadSettings());
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

  final BackendClient? _backend;
  final NativePttBridge _nativePtt;
  final CarBridge _carBridge;
  final MissionSharer _missionSharer;

  static const _maxTrackPoints = 5000;
  final List<TrackPoint> _track = [];
  final SettingsStore settings;

  /// Lower bound for scheduling a session refresh (tests use a short one).
  final Duration minSessionRefreshDelay;

  /// How often an active SOS call is repeated.
  final Duration sosRepeat;
  late final StreamSubscription<NativePttButton> _nativeButtonSubscription;
  late final StreamSubscription<String> _nativeErrorSubscription;
  late final StreamSubscription<CarReply> _carReplySubscription;
  late final StreamSubscription<RoomData> _roomDataSubscription;
  bool _roomWasConnected = false;
  Timer? _refreshTimer;
  DateTime? _lastInternetPositionAt;
  LatLng? _lastInternetPosition;
  bool _appInForeground = true;
  bool _volumeKeyPtt = false;
  String? _lastCarTargets;
  String? _lastNativePttStatus;
  final AuthService _authService;
  late final PttController _ptt;
  final LocationService _locationService;
  final MeshPacketRepository _meshPacketRepository;
  final MeshRadio _meshtasticBleService;
  final TacticalStateStore _stateStore;
  final MeshtasticMessageEncoder _messageEncoder =
      const MeshtasticMessageEncoder();
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
  late final Timer _agingTimer;

  bool _disposed = false;
  AuthSession? _session;
  int _selectedGroupIndex = 0;
  double _fontScale = 1.0;
  DateTime? _lastLocationPersistAt;
  LocationState _locationState = LocationState.idle;
  MeshtasticBleState _bleState = MeshtasticBleState.idle;
  MeshPacketDiagnostics _packetDiagnostics = MeshPacketDiagnostics.empty;

  final List<MeshNode> _nodes = MeshNode.demoNodes(DateTime.now());
  final List<MeshMessage> _messages = MeshMessage.demoMessages(DateTime.now());
  List<CommunicationGroup> _groups = CommunicationGroup.demoGroups;
  final Map<int, RadioChannel> _radioChannels = {};
  final List<TacticalWaypoint> _waypoints = [...TacticalWaypoint.demoWaypoints];

  /// User-facing notices (shown as snack bars).
  Stream<String> get notices => _noticeController.stream;

  AuthSession? get session => _session;
  List<MeshNode> get nodes => List.unmodifiable(_nodes);
  List<MeshNode> get peers => _nodes.where((node) => !node.isSelf).toList();
  MeshNode get selfNode => _nodes.firstWhere((node) => node.isSelf);
  List<MeshMessage> get messages => List.unmodifiable(_messages);
  List<TacticalWaypoint> get waypoints => List.unmodifiable(_waypoints);

  /// Own recorded trail, oldest first.
  List<TrackPoint> get track => List.unmodifiable(_track);
  PttController get ptt => _ptt;
  bool get pttActive => _ptt.status == PttStatus.transmitting;

  /// PTT joined (or demo) and usable.
  bool get voiceOnline => switch (_ptt.status) {
    PttStatus.ready || PttStatus.transmitting || PttStatus.receiving => true,
    _ => false,
  };
  bool get meshConnected => _bleState.status == MeshtasticBleStatus.connected;
  double get fontScale => _fontScale;
  LocationState get locationState => _locationState;
  MeshtasticBleState get bleState => _bleState;
  MeshPacketDiagnostics get packetDiagnostics => _packetDiagnostics;

  List<CommunicationGroup> get allowedGroups {
    final session = _session;
    if (session == null) {
      return const [];
    }
    return _groups
        .where((group) => session.allowedGroupIds.contains(group.id))
        .toList();
  }

  /// Channel slots reported by the connected T-Beam (empty until its
  /// config has been received).
  List<RadioChannel> get radioChannels =>
      _radioChannels.values.toList()..sort((a, b) => a.index - b.index);

  /// Groups whose Meshtastic channel is not enabled on the T-Beam: their
  /// messages would not reach the team.
  List<String> get channelWarnings {
    if (_radioChannels.isEmpty) {
      return const [];
    }
    return [
      for (final group in allowedGroups)
        if (!(_radioChannels[group.channelIndex]?.enabled ?? false))
          'Skupina ${group.name} používá kanál ${group.channelIndex}, '
              'který T-Beam nemá zapnutý.',
    ];
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
    unawaited(_locationStateSubscription.cancel());
    unawaited(_locationFixSubscription.cancel());
    unawaited(_locationService.dispose());
    unawaited(_meshtasticBleService.dispose());
    unawaited(_meshPacketRepository.dispose());
    _ptt
      ..removeListener(_onPttChanged)
      ..dispose();
    unawaited(_nativeButtonSubscription.cancel());
    unawaited(_nativeErrorSubscription.cancel());
    unawaited(_carReplySubscription.cancel());
    unawaited(_roomDataSubscription.cancel());
    _refreshTimer?.cancel();
    _sosTimer?.cancel();
    if (_lastNativePttStatus != null) {
      unawaited(_nativePtt.hide());
    }
    _backend?.close();
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
    _groups = session.groupDefinitions.isEmpty
        ? CommunicationGroup.demoGroups
        : [
            for (final group in session.groupDefinitions)
              CommunicationGroup.configured(
                id: group.id,
                name: group.name,
                channelIndex: group.channelIndex,
                pttEnabled: group.pttEnabled,
                description: group.description,
              ),
          ];
    _selectedGroupIndex = await _preferredGroupIndex(session.userName);
    _notify();
    _scheduleSessionRefresh(session);
    unawaited(_locationService.start());
    unawaited(_restorePersistedState(session.userName));
    unawaited(_joinSelectedGroupPtt());
    return null;
  }

  // --- Session lifetime ------------------------------------------------------

  /// Refreshes backend sessions at 75 % of their lifetime so a long
  /// operation never runs into the token expiry.
  void _scheduleSessionRefresh(AuthSession session, {Duration? after}) {
    _refreshTimer?.cancel();
    final lifetime = session.expiresIn;
    if (session.isDemo || lifetime == null) {
      return;
    }
    var delay = after ?? lifetime * 0.75;
    if (delay < minSessionRefreshDelay) {
      delay = minSessionRefreshDelay;
    }
    _refreshTimer = Timer(delay, () => unawaited(_refreshSession()));
  }

  Future<void> _refreshSession() async {
    final session = _session;
    final token = session?.sessionToken;
    final backend = _backend;
    if (session == null || token == null || backend == null) {
      return;
    }
    try {
      final refreshed = await backend.refresh(token);
      if (!identical(_session, session)) {
        return; // logged out or switched meanwhile
      }
      final updated = session.withToken(refreshed.token, refreshed.expiresIn);
      _session = updated;
      _scheduleSessionRefresh(updated);
    } on BackendException catch (error) {
      if (!identical(_session, session)) {
        return;
      }
      if (error.statusCode == 401) {
        await endSession(
          'Relace vypršela nebo byla zrušena velitelem. Přihlas se znovu.',
        );
      } else {
        // Offline for a moment: try again soon, the token is still valid.
        _scheduleSessionRefresh(session, after: const Duration(minutes: 1));
      }
    }
  }

  /// Returns to the login screen without wiping the encrypted store: the
  /// same user gets everything back after logging in again, anyone else
  /// sees nothing of it. Used when the backend no longer accepts the
  /// session.
  Future<void> endSession(String reason) async {
    if (_session == null) {
      return;
    }
    _refreshTimer?.cancel();
    await _persistState();
    _session = null;
    _selectedGroupIndex = 0;
    _groups = CommunicationGroup.demoGroups;
    await _ptt.leave();
    await _locationService.stop();
    _resetOperationalData();
    _notice(reason);
    _notify();
  }

  /// Adds a trail point every 15 m or once a minute while moving slowly.
  void _recordTrack(LocationFix fix) {
    if (_session == null) {
      return;
    }
    final point = TrackPoint(
      latitude: fix.latitude,
      longitude: fix.longitude,
      altitudeM: fix.altitudeM.round(),
      at: fix.timestamp,
    );
    final last = _track.lastOrNull;
    if (last != null &&
        geo.distanceKm(last.latLng, point.latLng) < 0.015 &&
        point.at.difference(last.at) < const Duration(minutes: 1)) {
      return;
    }
    _track.add(point);
    if (_track.length > _maxTrackPoints) {
      _track.removeAt(0);
    }
  }

  void clearTrack() {
    _track.clear();
    _notify();
    unawaited(_persistState());
  }

  /// Shares the mission as GPX (waypoints + trail) and a CSV message log.
  Future<void> exportMission() async {
    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    final stamp =
        '${now.year}${two(now.month)}${two(now.day)}-${two(now.hour)}${two(now.minute)}';
    final name = 'Mise ${selfNode.callSign} $stamp';
    try {
      await _missionSharer.share([
        ExportFile(
          name: 'mise-$stamp.gpx',
          mimeType: 'application/gpx+xml',
          content: buildMissionGpx(
            missionName: name,
            track: _track,
            waypoints: _waypoints,
            exportedAt: now,
          ),
        ),
        ExportFile(
          name: 'zpravy-$stamp.csv',
          mimeType: 'text/csv',
          content: buildMessagesCsv(messages: _messages, groups: _groups),
        ),
      ], subject: name);
    } catch (error) {
      _notice('Export se nepodařil: $error');
    }
  }

  void _resetOperationalData() {
    _stopSosSilently();
    _track.clear();
    _replaceNodes(MeshNode.demoNodes(DateTime.now()));
    _messages
      ..clear()
      ..addAll(MeshMessage.demoMessages(DateTime.now()));
    _waypoints
      ..clear()
      ..addAll(TacticalWaypoint.demoWaypoints);
  }

  /// Panic wipe: logout plus removal of all preferences, without asking
  /// anything and without contacting the backend. Offline map tiles are
  /// wiped by the caller (OfflineMapsController).
  Future<void> emergencyWipe() async {
    _stopSosSilently();
    await logout();
    await settings.clearAll();
    _fontScale = 1.0;
    _volumeKeyPtt = false;
    _nightMode = false;
    _sharePositionToMesh = true;
    unawaited(_nativePtt.setVolumeKeyPtt(false));
    _notify();
  }

  /// Ends the session and wipes everything stored on the device.
  Future<void> logout() async {
    // Drop the session first so no in-flight persist can rewrite the store.
    _refreshTimer?.cancel();
    _session = null;
    _selectedGroupIndex = 0;
    _groups = CommunicationGroup.demoGroups;
    _notify();
    await _authService.logout();
    await _ptt.leave();
    unawaited(_carBridge.clearMessages());
    unawaited(_carBridge.updateTargets(const []));
    _lastCarTargets = null;
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
    _resetOperationalData();
    _notify();
  }

  // --- Settings / devices --------------------------------------------------

  void setFontScale(double value) {
    _fontScale = value;
    unawaited(settings.setFontScale(value));
    _notify();
  }

  Future<void> _loadSettings() async {
    final fontScale = await settings.fontScale();
    final volumeKey = await settings.volumeKeyPtt();
    _nightMode = await settings.nightMode();
    _sharePositionToMesh = await settings.sharePositionToMesh();
    if (_disposed) {
      return;
    }
    if (fontScale != null) {
      _fontScale = fontScale.clamp(0.85, 1.35);
    }
    if (volumeKey) {
      _volumeKeyPtt = true;
      unawaited(_nativePtt.setVolumeKeyPtt(true));
    }
    _notify();
  }

  Future<int> _preferredGroupIndex(String userName) async {
    final groupId = await settings.groupFor(userName);
    final index = allowedGroups.indexWhere((group) => group.id == groupId);
    return index == -1 ? 0 : index;
  }

  Future<void> connectRadio() => _meshtasticBleService.startAutoConnect();

  /// Received frames as a text recording (see PacketRecording).
  String exportPacketRecording() => _meshPacketRepository.recording.serialize(
    comment:
        'Tactical Mesh FromRadio recording ${DateTime.now().toUtc().toIso8601String()}',
  );

  Future<void> startLocation() => _locationService.start();

  Future<void> openLocationSettings() => _locationService.openSettings();

  // --- PTT -----------------------------------------------------------------

  void setPttActive(bool value) {
    if (value) {
      unawaited(_ptt.press());
    } else {
      unawaited(_ptt.release());
    }
  }

  Future<void> reconnectPtt() => _joinSelectedGroupPtt();

  bool get volumeKeyPtt => _volumeKeyPtt;

  bool _nightMode = false;
  bool _sharePositionToMesh = true;
  DateTime? _lastMeshPositionAt;
  LatLng? _lastMeshPosition;

  /// Phone GPS is broadcast into the mesh (POSITION_APP), so teammates
  /// see us even when the T-Beam has no GPS fix of its own.
  bool get sharePositionToMesh => _sharePositionToMesh;

  void setSharePositionToMesh(bool enabled) {
    _sharePositionToMesh = enabled;
    unawaited(settings.setSharePositionToMesh(enabled));
    if (enabled) {
      unawaited(_sharePositionToRadio(force: true));
    }
    _notify();
  }

  /// At most once a minute, or after 50 m of movement.
  Future<void> _sharePositionToRadio({
    LocationFix? latest,
    bool force = false,
  }) async {
    if (!_sharePositionToMesh || !meshConnected || _session == null) {
      return;
    }
    final fix = latest ?? _locationState.lastFix;
    if (fix == null) {
      return;
    }
    final position = LatLng(fix.latitude, fix.longitude);
    final now = DateTime.now();
    final last = _lastMeshPosition;
    final lastAt = _lastMeshPositionAt;
    if (!force &&
        last != null &&
        lastAt != null &&
        now.difference(lastAt) < const Duration(minutes: 1) &&
        geo.distanceKm(last, position) < 0.05) {
      return;
    }
    _lastMeshPosition = position;
    _lastMeshPositionAt = now;
    try {
      await _meshtasticBleService.writeToRadio(
        _messageEncoder.encodePosition(
          latitude: fix.latitude,
          longitude: fix.longitude,
          altitudeM: fix.altitudeM.round(),
          time: fix.timestamp,
          packetId: _newPacketId(),
        ),
      );
    } catch (_) {
      // Radio went away; the next fix after reconnecting will try again.
      _lastMeshPositionAt = null;
    }
  }

  /// Red, dimmed display for preserving night vision.
  bool get nightMode => _nightMode;

  void setNightMode(bool enabled) {
    _nightMode = enabled;
    unawaited(settings.setNightMode(enabled));
    _notify();
  }

  /// Volume-down as hold-to-talk while the app is in front (Android).
  void setVolumeKeyPtt(bool enabled) {
    _volumeKeyPtt = enabled;
    unawaited(_nativePtt.setVolumeKeyPtt(enabled));
    unawaited(settings.setVolumeKeyPtt(enabled));
    _notify();
  }

  /// Set by the app shell; message notifications only when in background.
  void setAppInForeground(bool value) => _appInForeground = value;

  void _onPttChanged() {
    _syncNativePtt();
    final connected = _ptt.roomConnected;
    if (connected && !_roomWasConnected) {
      // New room (login, group change, reconnect): announce right away.
      unawaited(_shareInternetPosition(force: true));
      if (!meshConnected) {
        unawaited(_resendPending());
      }
    }
    _roomWasConnected = connected;
    _notify();
  }

  // --- Internet fallback (group room data channel) ---------------------------

  /// Own position to the group room, at most every 30 s or after 25 m.
  Future<void> _shareInternetPosition({bool force = false}) async {
    if (!_ptt.roomConnected || _session == null) {
      return;
    }
    final self = selfNode;
    final now = DateTime.now();
    final last = _lastInternetPosition;
    final lastAt = _lastInternetPositionAt;
    if (!force &&
        last != null &&
        lastAt != null &&
        now.difference(lastAt) < const Duration(seconds: 30) &&
        geo.distanceKm(last, self.latLng) < 0.025) {
      return;
    }
    _lastInternetPosition = self.latLng;
    _lastInternetPositionAt = now;
    await _ptt.sendRoomData(
      RoomTopic.position,
      utf8.encode(
        jsonEncode({
          'v': 1,
          'callSign': self.callSign,
          'nodeNum': self.nodeNum,
          'lat': self.latitude,
          'lon': self.longitude,
          'alt': self.altitudeM,
          'battery': ?self.batteryPercent,
          'at': now.toUtc().toIso8601String(),
        }),
      ),
    );
  }

  void _onRoomData(RoomData data) {
    if (_session == null || data.from == _ptt.identity) {
      return;
    }
    final Map<String, dynamic> message;
    try {
      message = jsonDecode(utf8.decode(data.data)) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    final changed = switch (data.topic) {
      RoomTopic.position => _applyInternetPosition(data.from, message),
      RoomTopic.text => _applyInternetText(data.from, message),
      _ => false,
    };
    if (changed) {
      _notify();
      unawaited(_persistState());
    }
  }

  bool _applyInternetPosition(String from, Map<String, dynamic> message) {
    final lat = (message['lat'] as num?)?.toDouble();
    final lon = (message['lon'] as num?)?.toDouble();
    final at = DateTime.tryParse(message['at']?.toString() ?? '');
    final now = DateTime.now();
    if (lat == null ||
        lon == null ||
        lat.abs() > 90 ||
        lon.abs() > 180 ||
        at == null ||
        now.difference(at) > const Duration(minutes: 10) ||
        at.difference(now) > const Duration(seconds: 30)) {
      return false;
    }
    final self = selfNode;
    final announced = (message['nodeNum'] as num?)?.toInt();
    // A member with a radio reports its node number, so LoRa and internet
    // updates merge into one node; otherwise derive a stable local one.
    var index = announced == null
        ? -1
        : _nodes.indexWhere((n) => !n.isSelf && n.nodeNum == announced);
    final nodeNum = index != -1 ? announced! : _internetNodeNum(from);
    if (nodeNum == self.nodeNum) {
      return false;
    }
    if (index == -1) {
      index = _nodes.indexWhere((n) => n.nodeNum == nodeNum);
    }
    final existing = index == -1 ? null : _nodes[index];
    if (existing != null && !existing.lastSeenAt.isBefore(at)) {
      return false; // we already have a newer fix (e.g. via LoRa)
    }
    final callSign = message['callSign']?.toString().trim();
    final updated = MeshNode(
      nodeNum: nodeNum,
      callSign: callSign == null || callSign.isEmpty
          ? existing?.callSign ?? from
          : callSign,
      latitude: lat,
      longitude: lon,
      altitudeM: (message['alt'] as num?)?.toInt() ?? existing?.altitudeM ?? 0,
      batteryPercent:
          (message['battery'] as num?)?.toInt() ?? existing?.batteryPercent,
      lastSeenAt: at.toLocal(),
      viaInternet: true,
    ).relativeTo(self);
    if (index == -1) {
      _nodes.add(updated);
    } else {
      _nodes[index] = updated;
    }
    return true;
  }

  /// Stable node number for a member known only by identity (outside the
  /// range Meshtastic hands out to real radios).
  static int _internetNodeNum(String identity) {
    var hash = 0x811C9DC5;
    for (final unit in utf8.encode(identity)) {
      hash = ((hash ^ unit) * 0x01000193) & 0xFFFFFFFF;
    }
    return 0x7E000000 | (hash & 0x00FFFFFF);
  }

  /// Team text received over the internet (sender had no radio link).
  bool _applyInternetText(String from, Map<String, dynamic> message) {
    final text = message['text']?.toString().trim() ?? '';
    final id = (message['id'] as num?)?.toInt();
    final groupId = message['groupId']?.toString();
    final at = DateTime.tryParse(message['at']?.toString() ?? '');
    if (text.isEmpty || id == null || at == null) {
      return false;
    }
    // The room belongs to the selected group; never file it elsewhere.
    final group = selectedGroup;
    if (groupId != group.id) {
      return false;
    }
    final fromNode = _internetNodeNum(from);
    if (_messages.any(
      (m) =>
          m.delivery == MessageDelivery.received &&
          m.packetId == id &&
          m.fromNode == fromNode,
    )) {
      return false;
    }
    final callSign = message['callSign']?.toString().trim();
    final sender = callSign == null || callSign.isEmpty ? from : callSign;
    _applyStructuredText(text, sender: sender);
    final incoming = MeshMessage(
      sender: sender,
      body: text,
      sentAt: at.toLocal(),
      groupId: group.id,
      targetLabel: group.name,
      priority: message['priority'] == true,
      packetId: id,
      fromNode: fromNode,
      viaInternet: true,
    );
    _messages.insert(0, incoming);
    if (!_appInForeground) {
      unawaited(
        _carBridge.notifyMessage(
          groupId: group.id,
          groupName: group.name,
          sender: sender,
          body: text,
          sentAt: incoming.sentAt,
        ),
      );
    }
    return true;
  }

  /// Sends a group message over the room when no radio is connected.
  /// Direct messages and other groups' traffic need the radio.
  Future<bool> _sendViaInternet(MeshMessage message) async {
    if (meshConnected ||
        message.toNode != null ||
        message.groupId != selectedGroup.id ||
        !_ptt.roomConnected) {
      return false;
    }
    return _ptt.sendRoomData(
      RoomTopic.text,
      utf8.encode(
        jsonEncode({
          'v': 1,
          'id': message.packetId,
          'callSign': message.sender,
          'groupId': message.groupId,
          'text': message.body,
          'priority': message.priority,
          'at': message.sentAt.toUtc().toIso8601String(),
        }),
      ),
    );
  }

  /// Mirrors PTT state into the Android foreground service notification;
  /// the service runs whenever PTT is joined so audio survives screen-off.
  void _syncNativePtt() {
    final ptt = _ptt;
    if (ptt.status == PttStatus.offline ||
        ptt.status == PttStatus.disabled ||
        ptt.isDemo) {
      if (_lastNativePttStatus != null) {
        _lastNativePttStatus = null;
        unawaited(_nativePtt.hide());
      }
      return;
    }
    final status = switch (ptt.status) {
      PttStatus.connecting => 'připojuji',
      PttStatus.ready => 'připraveno',
      PttStatus.transmitting => 'vysílám',
      PttStatus.receiving => 'mluví ${ptt.speaker ?? '?'}',
      PttStatus.error => ptt.error ?? 'chyba spojení',
      PttStatus.offline || PttStatus.disabled => '',
    };
    final key = '${ptt.channel}|$status';
    if (key == _lastNativePttStatus) {
      return;
    }
    _lastNativePttStatus = key;
    unawaited(_nativePtt.show(channel: ptt.channel, status: status));
  }

  void _onNativeButton(NativePttButton button) {
    switch (button) {
      case NativePttButton.down:
        unawaited(_ptt.press());
      case NativePttButton.up:
        unawaited(_ptt.release());
      case NativePttButton.toggle:
        unawaited(
          _ptt.status == PttStatus.transmitting ? _ptt.release() : _ptt.press(),
        );
    }
  }

  void _onCarReply(CarReply reply) {
    if (_session == null ||
        !allowedGroups.any((group) => group.id == reply.groupId)) {
      return;
    }
    unawaited(
      sendMeshText(MeshMessageDraft(text: reply.text, groupId: reply.groupId)),
    );
  }

  /// Pushes the nearest/priority targets to Android Auto when they change.
  void _syncCarTargets() {
    if (_session == null) {
      return;
    }
    final solutions = TacticalNavSolution.fromMission(
      self: selfNode,
      nodes: _nodes,
      waypoints: _waypoints,
    ).take(6);
    final targets = [
      for (final solution in solutions)
        if (_targetPosition(solution) case final position?)
          CarTargetData(
            title: solution.label,
            kind: solution.kind.label,
            latitude: position.latitude,
            longitude: position.longitude,
            distanceKm: solution.distanceKm,
            bearingDeg: solution.bearingDeg,
            priority: solution.priority,
          ),
    ];
    final signature = [
      for (final t in targets)
        '${t.title}:${t.distanceKm.toStringAsFixed(2)}:${t.bearingDeg.round()}',
    ].join(',');
    if (signature == _lastCarTargets) {
      return;
    }
    _lastCarTargets = signature;
    unawaited(_carBridge.updateTargets(targets));
  }

  LatLng? _targetPosition(TacticalNavSolution solution) {
    final waypoint = solution.waypoint;
    if (waypoint != null) {
      return waypoint.latLng;
    }
    for (final node in _nodes) {
      if (!node.isSelf && node.callSign == solution.label) {
        return node.latLng;
      }
    }
    return null;
  }

  void selectGroup(int index) {
    final session = _session;
    if (session == null) {
      return;
    }
    _selectedGroupIndex = index;
    unawaited(settings.setGroupFor(session.userName, selectedGroup.id));
    _notify();
    unawaited(_joinSelectedGroupPtt());
  }

  Future<void> _joinSelectedGroupPtt() async {
    if (_session == null) {
      return;
    }
    final group = selectedGroup;
    if (!group.pttEnabled) {
      await _ptt.disable(group.name);
      return;
    }
    await _ptt.joinGroup(group.id, group.name);
  }

  Future<PttJoinInfo> _joinPtt(String groupId) async {
    final token = _session?.sessionToken;
    if (token == null) {
      throw const BackendException(401, 'no_session');
    }
    try {
      return await _backend!.joinPtt(token, groupId);
    } on BackendException catch (error) {
      if (error.statusCode == 401) {
        // Revoked/blocked/unbound: the whole session is gone, not just PTT.
        unawaited(
          endSession(
            'Relace byla ukončena (zrušena, zablokovaný účet nebo odpojené '
            'zařízení). Přihlas se znovu.',
          ),
        );
      }
      rethrow;
    }
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
    _recordTrack(fix);
    _notify();
    unawaited(_shareInternetPosition());
    unawaited(_sharePositionToRadio(latest: fix));

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
          // A (re)connected radio sends its whole config again.
          _radioChannels.clear();
          changed = _adoptRadioNodeNum(event.nodeNum) || changed;
        case DecodedMeshEventType.channel:
          final index = event.channelIndex ?? 0;
          _radioChannels[index] = RadioChannel(
            index: index,
            name: event.channelName ?? '',
            role: event.channelRole ?? 0,
          );
          changed = true;
        case DecodedMeshEventType.configComplete:
          // Handshake done: the radio accepts traffic again.
          unawaited(_resendPending());
          unawaited(_sharePositionToRadio(force: true));
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
    _applyStructuredText(text, sender: sender);
    final message = MeshMessage(
      sender: sender,
      body: text,
      sentAt: event.heardAt ?? DateTime.now(),
      groupId: group.id,
      targetLabel: target,
      packetId: packetId,
      fromNode: event.from,
    );
    _messages.insert(0, message);
    if (!_appInForeground &&
        allowedGroups.any((allowed) => allowed.id == group.id)) {
      unawaited(
        _carBridge.notifyMessage(
          groupId: group.id,
          groupName: group.name,
          sender: sender,
          body: text,
          sentAt: message.sentAt,
        ),
      );
    }
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
    _applyStructuredText(draft.text, sender: self.callSign);
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

  /// Turns structured report text into map data: shared waypoints and
  /// CONTACT reports (plotted as a DANGER point at the estimated position).
  void _applyStructuredText(String text, {required String sender}) {
    final now = DateTime.now();
    final sos = SosSignal.parse(text);
    if (sos != null) {
      // Our own outgoing calls are shown by the "SOS AKTIVNÍ" banner.
      if (sender != selfNode.callSign) {
        _applySos(sos, sender: sender, at: now);
      }
      return;
    }
    final shared = TacticalWaypoint.parseShareText(
      text,
      sharedBy: sender,
      receivedAt: now,
    );
    if (shared != null) {
      _upsertWaypoint(shared);
      return;
    }
    final contact = ContactReport.parse(text);
    if (contact != null) {
      String two(int value) => value.toString().padLeft(2, '0');
      final position = contact.position;
      _waypoints.add(
        TacticalWaypoint(
          code: _uniqueWaypointCode(
            'CONTACT-${two(now.hour)}${two(now.minute)}',
            TacticalWaypointType.danger,
          ),
          type: TacticalWaypointType.danger,
          latitude: position.latitude,
          longitude: position.longitude,
          note: [
            contact.contactType,
            contact.size,
            if (contact.note.isNotEmpty) contact.note,
          ].join(' / '),
          priority: true,
          sharedBy: sender,
          createdAt: now,
        ),
      );
    }
  }

  // --- SOS ----------------------------------------------------------------------

  static const _sosAlertLifetime = Duration(minutes: 30);
  bool _sosActive = false;
  Timer? _sosTimer;
  final Map<String, SosAlert> _sosAlerts = {};

  /// Our own distress call is being repeated.
  bool get sosActive => _sosActive;

  /// Teammates' calls not yet acknowledged here and repeated within the
  /// last 30 minutes, newest first.
  List<SosAlert> get activeSosAlerts {
    final cutoff = DateTime.now().subtract(_sosAlertLifetime);
    return _sosAlerts.values
        .where((alert) => !alert.acknowledged && alert.lastAt.isAfter(cutoff))
        .toList()
      ..sort((a, b) => b.lastAt.compareTo(a.lastAt));
  }

  /// Starts repeating a distress call with the current position every
  /// minute until [stopSos].
  Future<void> startSos() async {
    if (_sosActive || _session == null) {
      return;
    }
    _sosActive = true;
    _notify();
    _sosTimer = Timer.periodic(sosRepeat, (_) => unawaited(_sendSosCall()));
    await _sendSosCall();
  }

  Future<void> stopSos() async {
    if (!_sosActive) {
      return;
    }
    _sosTimer?.cancel();
    _sosActive = false;
    _notify();
    await sendMeshText(
      MeshMessageDraft(
        text: SosSignal.cancel(selfNode.callSign),
        groupId: selectedGroup.id,
        priority: true,
      ),
    );
  }

  Future<void> _sendSosCall() async {
    if (!_sosActive || _session == null) {
      return;
    }
    final self = selfNode;
    unawaited(_shareInternetPosition(force: true));
    await sendMeshText(
      MeshMessageDraft(
        text: SosSignal.call(
          callSign: self.callSign,
          mgrs: self.mgrs,
          latitude: self.latitude,
          longitude: self.longitude,
        ),
        groupId: selectedGroup.id,
        priority: true,
      ),
    );
  }

  /// "Beru": tells the caller help is on it and hides the banner here.
  Future<void> acknowledgeSos(SosAlert alert) async {
    final current = _sosAlerts[alert.callSign];
    if (current == null) {
      return;
    }
    _sosAlerts[alert.callSign] = current.copyWith(acknowledged: true);
    _notify();
    await sendMeshText(
      MeshMessageDraft(
        text: SosSignal.ack(from: selfNode.callSign, to: alert.callSign),
        groupId: selectedGroup.id,
        priority: true,
      ),
    );
  }

  void _applySos(
    SosSignal signal, {
    required String sender,
    required DateTime at,
  }) {
    switch (signal) {
      case SosCall(
        :final callSign,
        :final mgrs,
        :final latitude,
        :final longitude,
      ):
        final name = callSign ?? sender;
        final previous = _sosAlerts[name];
        _sosAlerts[name] = SosAlert(
          callSign: name,
          lastAt: at,
          mgrs: mgrs ?? previous?.mgrs,
          latitude: latitude ?? previous?.latitude,
          longitude: longitude ?? previous?.longitude,
          // A repeated call after "Beru" stays acknowledged.
          acknowledged: previous?.acknowledged ?? false,
        );
        if (latitude != null && longitude != null) {
          _upsertWaypoint(
            TacticalWaypoint(
              code: 'SOS-$name',
              type: TacticalWaypointType.danger,
              latitude: latitude,
              longitude: longitude,
              note: 'SOS ${_clock(at)}',
              priority: true,
              sharedBy: name,
              createdAt: at,
            ),
          );
        }
      case SosCancel(:final callSign):
        _sosAlerts.remove(callSign);
        _waypoints.removeWhere((w) => w.code == 'SOS-$callSign');
      case SosAck():
        break; // shown as a normal message
    }
  }

  static String _clock(DateTime at) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(at.hour)}:${two(at.minute)}';
  }

  void _stopSosSilently() {
    _sosTimer?.cancel();
    _sosActive = false;
    _sosAlerts.clear();
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
    var viaInternet = false;
    try {
      await _meshtasticBleService.writeToRadio(bytes);
    } catch (_) {
      viaInternet = await _sendViaInternet(message);
      if (!viaInternet) {
        delivery = MessageDelivery.notSent;
        if (!_resending) {
          _notice('T-Beam není připojen: zprávu lze odeslat znovu ze seznamu.');
        }
      }
    }

    _replaceOutgoing(
      packetId,
      (current) => current.delivery == MessageDelivery.sending
          ? current.copyWith(delivery: delivery, viaInternet: viaInternet)
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

  bool _resending = false;

  /// Sends messages that could not be handed to any transport, oldest
  /// first, once a radio or the group room is available again. Messages
  /// the mesh explicitly refused (failed) stay for a manual retry.
  Future<void> _resendPending() async {
    if (_resending || _session == null) {
      return;
    }
    final cutoff = DateTime.now().subtract(const Duration(hours: 24));
    final pending = _messages
        .where(
          (m) =>
              m.delivery == MessageDelivery.notSent && m.sentAt.isAfter(cutoff),
        )
        .toList()
        .reversed
        .toList();
    if (pending.isEmpty) {
      return;
    }
    _resending = true;
    var sent = 0;
    try {
      for (final message in pending) {
        await retryMessage(message);
        final delivery = _messages
            .where((m) => m.body == message.body && m.sentAt == message.sentAt)
            .map((m) => m.delivery)
            .firstOrNull;
        if (delivery == MessageDelivery.sent ||
            delivery == MessageDelivery.delivered) {
          sent++;
        }
      }
    } finally {
      _resending = false;
    }
    if (sent > 0) {
      _notice('Odesláno $sent čekajících zpráv.');
    }
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
      final restoredTrack = snapshot.track?.map(TrackPoint.fromJson).toList();
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
      if (restoredTrack != null) {
        _track
          ..clear()
          ..addAll(restoredTrack);
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
        track: [for (final point in _track) point.toJson()],
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
      _syncCarTargets();
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
