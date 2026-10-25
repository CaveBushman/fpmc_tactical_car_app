import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../models/geo.dart' as geo;
import '../models/member_status.dart';
import '../models/mission_event.dart';
import '../models/rendezvous.dart';
import '../models/sun.dart' as sun;
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
import 'battery_watch.dart';
import 'contact_watch.dart';
import 'danger_proximity.dart';
import 'member_status_board.dart';
import 'mission_log.dart';
import 'mission_recorder.dart';
import 'peer_trails.dart';
import 'ptt_controller.dart';
import 'session_keeper.dart';
import 'sos_coordinator.dart';
import 'unread_counter.dart';
import 'user_preferences.dart';
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
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now,
       _backend = backend,
       _nativePtt = nativePtt ?? NativePttBridge.platform(),
       _carBridge = carBridge ?? CarBridge.platform(),
       _mission = MissionRecorder(sharer: missionSharer),
       _authService =
           authService ??
           (backend == null ? AuthService() : RemoteAuthService(backend)),
       _locationService = locationService ?? GeolocatorLocationService(),
       _meshPacketRepository = meshPacketRepository ?? MeshPacketRepository(),
       _meshtasticBleService = meshtasticBleService ?? MeshtasticBleService(),
       _stateStore = stateStore ?? const TacticalStateStore() {
    _sessionKeeper = SessionKeeper(
      refresh: (token) => _backend!.refresh(token),
      currentSession: () => _session,
      onRefreshed: (updated) => _session = updated,
      onRejected: () => endSession(
        'Relace vypršela nebo byla zrušena velitelem. Přihlas se znovu.',
      ),
      minDelay: minSessionRefreshDelay,
    );
    _sos = SosCoordinator(
      repeat: sosRepeat,
      sendCall: _sendSosCall,
      sendCancel: () => _sendPriority(SosSignal.cancel(selfNode.callSign)),
      sendAck: (callSign) =>
          _sendPriority(SosSignal.ack(from: selfNode.callSign, to: callSign)),
      upsertPoint: _upsertWaypoint,
      removePoint: (code) => _waypoints.removeWhere((w) => w.code == code),
      onChanged: _notify,
    );
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
        // GPS only reports movement: a member standing still still has
        // to show up as alive on the commanders' situation page.
        unawaited(_reportToBackend());
      }
    });
  }

  /// Wall clock (tests pin it).
  final DateTime Function() _clock;
  final BackendClient? _backend;
  final NativePttBridge _nativePtt;
  final CarBridge _carBridge;
  final MissionRecorder _mission;
  final DangerProximity _danger = DangerProximity();
  final PeerTrails _peerTrails = PeerTrails();
  final ContactWatch _contactWatch = ContactWatch();
  final BatteryWatch _batteryWatch = BatteryWatch();
  double? _speedKmh;

  /// Smoothed own speed while moving, else walking pace; for ETAs.
  double get travelSpeedKmh => _speedKmh ?? TacticalNavSolution.walkingKmh;

  // --- Mission log ---------------------------------------------------------------

  final MissionLog _missionLog = MissionLog();

  /// Notable events of this mission, newest first.
  List<MissionEvent> get missionEvents => _missionLog.events;

  void _log(MissionEventKind kind, String text) {
    if (_session != null) {
      _missionLog.add(MissionEvent(at: _clock(), kind: kind, text: text));
    }
  }

  /// Alert when a teammate goes LOST.
  bool get lostContactAlerts => _prefs.lostContactAlerts;

  void setLostContactAlerts(bool enabled) {
    _prefs.lostContactAlerts = enabled;
    _notify();
  }

  /// Teammates heard this session who went silent, most recent first.
  List<LostContact> get lostContacts =>
      _prefs.lostContactAlerts && _session != null
      ? _contactWatch.alerts
      : const [];

  /// "Beru" on a lost-contact alert.
  void acknowledgeLostContact(LostContact contact) {
    _contactWatch.acknowledge(contact.nodeNum);
    _notify();
  }

  /// Teammates' positions over the last 30 minutes, by node number.
  Map<int, List<LatLng>> get peerTrails => _peerTrails.trails;
  late final SessionKeeper _sessionKeeper;
  late final SosCoordinator _sos;
  final SettingsStore settings;
  late final UserPreferences _prefs = UserPreferences(settings);

  /// Lower bound for scheduling a session refresh (tests use a short one).
  final Duration minSessionRefreshDelay;

  /// How often an active SOS call is repeated.
  final Duration sosRepeat;
  late final StreamSubscription<NativePttButton> _nativeButtonSubscription;
  late final StreamSubscription<String> _nativeErrorSubscription;
  late final StreamSubscription<CarReply> _carReplySubscription;
  late final StreamSubscription<RoomData> _roomDataSubscription;
  bool _roomWasConnected = false;
  DateTime? _lastInternetPositionAt;
  LatLng? _lastInternetPosition;
  bool _appInForeground = true;
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

  /// Nodes not heard for this long disappear from the map and the team
  /// list and are not saved any more.
  static const nodeExpiry = Duration(hours: 24);

  /// Self plus every node heard within [nodeExpiry].
  List<MeshNode> get nodes => List.unmodifiable(_nodes.where(_isCurrent));

  static bool _isCurrent(MeshNode node) =>
      node.isSelf || DateTime.now().difference(node.lastSeenAt) <= nodeExpiry;
  List<MeshNode> get peers => nodes.where((node) => !node.isSelf).toList();
  MeshNode get selfNode => _nodes.firstWhere((node) => node.isSelf);
  List<MeshMessage> get messages => List.unmodifiable(_messages);
  List<TacticalWaypoint> get waypoints => List.unmodifiable(_waypoints);

  /// Own recorded trail, oldest first.
  List<TrackPoint> get track => _mission.track;
  PttController get ptt => _ptt;
  bool get pttActive => _ptt.status == PttStatus.transmitting;

  /// PTT joined (or demo) and usable.
  bool get voiceOnline => switch (_ptt.status) {
    PttStatus.ready || PttStatus.transmitting || PttStatus.receiving => true,
    _ => false,
  };
  bool get meshConnected => _bleState.status == MeshtasticBleStatus.connected;
  double get fontScale => _prefs.fontScale;
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
    _sessionKeeper.cancel();
    _sos.dispose();
    if (_lastNativePttStatus != null) {
      unawaited(_nativePtt.hide());
    }
    _backend?.close();
    unawaited(_noticeController.close());
    super.dispose();
  }

  // --- Session -------------------------------------------------------------

  /// Returns an error message, or null on success.
  String? _lastUserName;

  /// A real (backend) session starts with nothing but the own node: the
  /// sample team, messages and points are for offline test accounts only
  /// and must never pass for real people or places. Saved state from an
  /// earlier session is restored on top as usual.
  void _startCleanMission(AuthSession session) {
    final self = selfNode;
    _replaceNodes([
      MeshNode(
        nodeNum: self.nodeNum,
        callSign: session.displayName.isEmpty
            ? session.userName.toUpperCase()
            : session.displayName,
        latitude: self.latitude,
        longitude: self.longitude,
        altitudeM: self.altitudeM,
        lastSeenAt: DateTime.now(),
        isSelf: true,
      ),
    ]);
    _messages.clear();
    _waypoints.clear();
  }

  /// Prefilled on the login screen: the last user who logged in here.
  String? get lastUserName => _lastUserName;

  Future<String?> login(String userName, String password) async {
    final result = await _authService.login(
      userName: userName,
      password: password,
    );
    if (!result.ok) {
      return result.errorMessage;
    }
    final session = result.session!;
    _lastUserName = session.userName;
    unawaited(settings.setLastUserName(session.userName));
    _session = session;
    if (!session.isDemo) {
      _startCleanMission(session);
    }
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
    _baseCode = await settings.baseFor(session.userName);
    _notify();
    if (_backend != null) {
      _sessionKeeper.schedule(session);
    }
    unawaited(_locationService.start());
    unawaited(_restorePersistedState(session.userName));
    unawaited(_joinSelectedGroupPtt());
    return null;
  }

  // --- Session lifetime ------------------------------------------------------

  /// Returns to the login screen without wiping the encrypted store: the
  /// same user gets everything back after logging in again, anyone else
  /// sees nothing of it. Used when the backend no longer accepts the
  /// session.
  Future<void> endSession(String reason) async {
    if (_session == null) {
      return;
    }
    _sessionKeeper.cancel();
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

  void clearTrack() {
    _mission.clear();
    _notify();
    unawaited(_persistState());
  }

  /// Shares the mission as GPX (waypoints + trail) and a CSV message log.
  Future<void> exportMission() async {
    try {
      await _mission.export(
        events: _missionLog.events,
        callSign: selfNode.callSign,
        waypoints: _waypoints,
        messages: _messages,
        groups: _groups,
      );
    } catch (error) {
      _notice('Export se nepodařil: $error');
    }
  }

  void _resetOperationalData() {
    _unread.clear();
    _danger.reset();
    _navTarget = null;
    _peerTrails.clear();
    _knownNames.clear();
    _lastHqMessageId = null;
    _pendingHqAcks.clear();
    _rendezvous = null;
    _lastBackendReportAt = null;
    _contactWatch.clear();
    _batteryWatch.clear();
    _speedKmh = null;
    _missionLog.clear();
    _courseDeg = null;
    _statuses.clear();
    _sos.reset();
    _mission.clear();
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
    _sos.reset();
    await logout();
    await settings.clearAll();
    _prefs.reset();
    _lastUserName = null;
    unawaited(_locationService.setPowerSaving(false));
    unawaited(_nativePtt.setVolumeKeyPtt(false));
    _notify();
  }

  /// Ends the session and wipes everything stored on the device.
  Future<void> logout() async {
    // Drop the session first so no in-flight persist can rewrite the store.
    _sessionKeeper.cancel();
    _baseCode = null;
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
    _prefs.fontScale = value;
    _notify();
  }

  Future<void> _loadSettings() async {
    await _prefs.load();
    _lastUserName = await settings.lastUserName();
    if (_disposed) {
      return;
    }
    if (_prefs.batterySaver) {
      unawaited(_locationService.setPowerSaving(true));
    }
    if (_prefs.volumeKeyPtt) {
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

  bool get volumeKeyPtt => _prefs.volumeKeyPtt;

  /// Coarser GPS and sparser position sharing (mesh every 5 min / 250 m,
  /// internet every 2 min / 100 m). SOS and forced updates are unaffected.
  bool get batterySaver => _prefs.batterySaver;

  void setBatterySaver(bool enabled) {
    _prefs.batterySaver = enabled;
    unawaited(_locationService.setPowerSaving(enabled));
    _notify();
  }

  double? _courseDeg;

  /// Direction of travel from GPS, kept while standing still so the map
  /// does not snap back north at every stop; null until we first move.
  double? get courseDeg => _courseDeg;

  /// Turn the map so the direction of travel points up.
  bool get mapHeadingUp => _prefs.mapHeadingUp;

  void setMapHeadingUp(bool enabled) {
    _prefs.mapHeadingUp = enabled;
    _notify();
  }

  /// One-tap message templates.
  List<String> get quickMessages => List.unmodifiable(_prefs.quickMessages);

  /// Blank lines are dropped; an empty list restores the defaults.
  void setQuickMessages(List<String> messages) {
    final cleaned = [
      for (final message in messages)
        if (message.trim().isNotEmpty) message.trim(),
    ];
    _prefs.quickMessages = cleaned.isEmpty
        ? SettingsStore.defaultQuickMessages
        : cleaned;
    _notify();
  }

  /// Full screen: the Android status and navigation bars are hidden and
  /// appear for a moment after a swipe from the edge.
  bool get hideSystemBars => _prefs.hideSystemBars;

  void setHideSystemBars(bool enabled) {
    _prefs.hideSystemBars = enabled;
    _notify();
  }

  /// Warn (banner + vibration) within 300 m of a DANGER point.
  bool get dangerAlerts => _prefs.dangerAlerts;

  void setDangerAlerts(bool enabled) {
    _prefs.dangerAlerts = enabled;
    _notify();
  }

  /// DANGER points we are close to, nearest first.
  List<DangerWarning> get dangerWarnings =>
      _prefs.dangerAlerts && _session != null ? _danger.warnings : const [];

  /// "Beru": hides the warning until we leave the point and come back.
  void dismissDanger(DangerWarning warning) {
    _danger.dismiss(warning.waypoint.code);
    _notify();
  }

  /// Runs before every notify, so position and point changes both count.
  void _checkDangers() {
    if (!_prefs.dangerAlerts || _session == null) {
      _danger.reset();
      return;
    }
    final entered = _danger.update(selfNode.latLng, _waypoints);
    for (final warning in entered) {
      _log(
        MissionEventKind.danger,
        'Přiblížení k ${warning.waypoint.code} '
        '(${warning.distanceM.round()} m)',
      );
      _notice(
        'POZOR: ${warning.waypoint.code} '
        '${warning.distanceM.round()} m, '
        'AZ ${warning.bearingDeg.round()}°',
      );
    }
  }

  // --- Navigation target -------------------------------------------------------

  /// Within this distance the target counts as reached.
  static const arrivalRadiusM = 50.0;

  NavTarget? _navTarget;

  /// Live solution for the chosen target; null = none chosen (the UI then
  /// points at the nearest target).
  TacticalNavSolution? get navTarget =>
      _navTarget?.resolve(self: selfNode, nodes: nodes, waypoints: _waypoints);

  void navigateTo(NavTarget target) {
    unawaited(Future(_persistState));
    _navTarget = target;
    final solution = navTarget;
    if (solution != null) {
      _log(MissionEventKind.navigation, 'Navigace k ${solution.label}');
    }
    _notify();
  }

  void clearNavTarget() {
    unawaited(Future(_persistState));
    _navTarget = null;
    _notify();
  }

  /// Runs before every notify: ends navigation on arrival or when the
  /// target disappeared (point deleted, teammate expired).
  void _checkNavTarget() {
    final target = _navTarget;
    if (target == null || _session == null) {
      return;
    }
    final solution = navTarget;
    if (solution == null) {
      _navTarget = null;
      _notice('Cíl navigace už neexistuje.');
    } else if (solution.distanceKm * 1000 <= arrivalRadiusM) {
      _navTarget = null;
      _log(MissionEventKind.navigation, 'Cíl ${solution.label} dosažen');
      _notice('Cíl ${solution.label} dosažen.');
    }
  }

  /// MGRS/UTM grid lines on the map.
  bool get mgrsGrid => _prefs.mgrsGrid;

  void setMgrsGrid(bool enabled) {
    _prefs.mgrsGrid = enabled;
    _notify();
  }

  /// Sends a map point to the selected group in a readable format.
  Future<void> sharePoint(LatLng point) => sendMeshText(
    MeshMessageDraft(
      text:
          'BOD | MGRS ${geo.formatMgrs(point.latitude, point.longitude)} | '
          'LAT ${point.latitude.toStringAsFixed(6)} | '
          'LON ${point.longitude.toStringAsFixed(6)}',
      groupId: selectedGroup.id,
    ),
  );
  DateTime? _lastMeshPositionAt;
  LatLng? _lastMeshPosition;

  /// Phone GPS is broadcast into the mesh (POSITION_APP), so teammates
  /// see us even when the T-Beam has no GPS fix of its own.
  bool get sharePositionToMesh => _prefs.sharePositionToMesh;

  void setSharePositionToMesh(bool enabled) {
    _prefs.sharePositionToMesh = enabled;
    if (enabled) {
      unawaited(_sharePositionToRadio(force: true));
    }
    _notify();
  }

  /// At most once a minute, or after 50 m of movement (5 min / 250 m in
  /// battery saver).
  Future<void> _sharePositionToRadio({
    LocationFix? latest,
    bool force = false,
  }) async {
    if (!_prefs.sharePositionToMesh || !meshConnected || _session == null) {
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
        now.difference(lastAt) <
            (_prefs.batterySaver
                ? const Duration(minutes: 5)
                : const Duration(minutes: 1)) &&
        geo.distanceKm(last, position) < (_prefs.batterySaver ? 0.25 : 0.05)) {
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

  /// Red, dimmed display for preserving night vision. In automatic mode
  /// it follows civil twilight at the own position.
  bool get nightMode {
    if (!_prefs.nightModeAuto) {
      return _prefs.nightMode;
    }
    final self = selfNode;
    return sun.isDark(_clock(), self.latitude, self.longitude);
  }

  /// Switching by hand ends the automatic mode.
  void setNightMode(bool enabled) {
    _prefs.nightMode = enabled;
    if (_prefs.nightModeAuto) {
      _prefs.nightModeAuto = false;
    }
    _notify();
  }

  bool get nightModeAuto => _prefs.nightModeAuto;

  void setNightModeAuto(bool enabled) {
    _prefs.nightModeAuto = enabled;
    _notify();
  }

  // --- Urgent member status -------------------------------------------------------

  final MemberStatusBoard _statuses = MemberStatusBoard();

  /// Teammates who reported being wounded or needing support within the
  /// last 30 minutes and have not been answered here, newest first.
  List<({String callSign, MemberStatusReport report})> get urgentStatuses =>
      _statuses.urgent(self: selfNode.callSign, now: _clock());

  /// "Beru": hides the alert until the member reports again.
  void acknowledgeStatus(String callSign) {
    if (_statuses.acknowledge(callSign)) {
      _notify();
    }
  }

  /// Navigates to [callSign] when their position is known.
  bool navigateToMember(String callSign) {
    for (final node in nodes) {
      if (!node.isSelf && node.callSign == callSign) {
        navigateTo(NavTarget.node(node.nodeNum));
        return true;
      }
    }
    _notice('Poloha $callSign není známa.');
    return false;
  }

  /// Volume-down as hold-to-talk while the app is in front (Android).
  void setVolumeKeyPtt(bool enabled) {
    _prefs.volumeKeyPtt = enabled;
    unawaited(_nativePtt.setVolumeKeyPtt(enabled));
    _notify();
  }

  /// Set by the app shell; message notifications only when in background.
  void setAppInForeground(bool value) {
    _appInForeground = value;
    if (value) {
      _markSelectedGroupRead();
    }
  }

  // --- Unread messages ---------------------------------------------------------

  final UnreadCounter _unread = UnreadCounter();
  bool _messagesVisible = false;

  /// Incoming messages in [groupId] not yet seen on the Messages tab.
  int unreadIn(String groupId) => _unread.countIn(groupId);

  /// Unread messages over all groups this user is in.
  int get unreadTotal => _unread.total(allowedGroups.map((group) => group.id));

  /// Set by the app shell: the Messages tab is on screen, showing the
  /// selected group.
  void setMessagesVisible(bool visible) {
    _messagesVisible = visible;
    _markSelectedGroupRead();
  }

  void _markSelectedGroupRead() {
    if (_messagesVisible &&
        _appInForeground &&
        _session != null &&
        _unread.markRead(selectedGroup.id)) {
      _notify();
    }
  }

  void _countIncoming(String groupId) {
    if (_messagesVisible && _appInForeground && groupId == selectedGroup.id) {
      return;
    }
    _unread.add(groupId);
  }

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

  /// Own position to the group room, at most every 30 s or after 25 m
  /// (2 min / 100 m in battery saver).
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
        now.difference(lastAt) <
            (_prefs.batterySaver
                ? const Duration(minutes: 2)
                : const Duration(seconds: 30)) &&
        geo.distanceKm(last, self.latLng) <
            (_prefs.batterySaver ? 0.1 : 0.025)) {
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
    _countIncoming(group.id);
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
    // The chosen target first, then nearest/priority ones.
    final chosen = navTarget;
    final solutions = [
      ?chosen,
      ...TacticalNavSolution.fromMission(
        self: selfNode,
        nodes: nodes,
        waypoints: _waypoints,
      ).where((solution) => _navTarget?.matches(solution) != true),
    ].take(6);
    final targets = [
      for (final solution in solutions)
        CarTargetData(
          title: solution.label,
          kind: solution.kind.label,
          latitude: solution.position.latitude,
          longitude: solution.position.longitude,
          distanceKm: solution.distanceKm,
          bearingDeg: solution.bearingDeg,
          priority: solution.priority || identical(solution, chosen),
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

  void selectGroup(int index) {
    final session = _session;
    if (session == null) {
      return;
    }
    _selectedGroupIndex = index;
    unawaited(settings.setGroupFor(session.userName, selectedGroup.id));
    _markSelectedGroupRead();
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

  // --- Member status -------------------------------------------------------------

  /// Last status reported by [callSign] (own one included), or null.
  MemberStatusReport? statusOf(String callSign) => _statuses.statusOf(callSign);

  /// Own status as last sent.
  MemberStatus? get ownStatus => _statuses.statusOf(selfNode.callSign)?.status;

  /// Tells the selected group how we are; urgent ones go as priority.
  Future<void> setOwnStatus(MemberStatus status) async {
    if (_session == null) {
      return;
    }
    final callSign = selfNode.callSign;
    _statuses.report(callSign, status, DateTime.now());
    unawaited(_persistState());
    unawaited(_reportToBackend(force: true));
    _log(MissionEventKind.status, 'Můj stav: ${status.label}');
    _notify();
    await sendMeshText(
      MeshMessageDraft(
        text: status.shareText(callSign),
        groupId: selectedGroup.id,
        priority: status.urgent,
      ),
    );
  }

  // --- Position report to the backend --------------------------------------------

  DateTime? _lastBackendReportAt;
  bool _backendReporting = false;

  /// Sends position, status and battery to the backend for the
  /// commanders' situation page: at most every 2 minutes (5 in battery
  /// saver), also without movement (the aging tick calls it with the last
  /// fix), and at once when [force]d (status change). Failures are silent:
  /// the next fix or tick tries again.
  Future<void> _reportToBackend({
    LocationFix? latest,
    bool force = false,
  }) async {
    final backend = _backend;
    final token = _session?.sessionToken;
    // The fix itself: the location state stream may not have caught up yet.
    final fix = latest ?? _locationState.lastFix;
    if (backend == null || token == null || fix == null || _backendReporting) {
      return;
    }
    final now = _clock();
    final last = _lastBackendReportAt;
    final interval = _prefs.batterySaver
        ? const Duration(minutes: 5)
        : const Duration(minutes: 2);
    if (!force && last != null && now.difference(last) < interval) {
      return;
    }
    _backendReporting = true;
    _lastBackendReportAt = now;
    try {
      final self = selfNode;
      final acks = _pendingHqAcks.toList()..sort();
      final incoming = await backend.reportPosition(
        token,
        sinceMessageId: _lastHqMessageId,
        acknowledgedMessageIds: acks,
        latitude: fix.latitude,
        longitude: fix.longitude,
        at: fix.timestamp,
        altitudeM: fix.altitudeM.round(),
        accuracyM: fix.accuracyM,
        // Only a connected T-Beam's own reading, never a stale or sample one.
        batteryPercent: meshConnected ? self.batteryPercent : null,
        status: ownStatus?.name,
      );
      if (acks.isNotEmpty) {
        _pendingHqAcks.removeAll(acks);
        unawaited(_persistState());
      }
      _applyHqMessages(incoming);
    } on BackendException {
      _lastBackendReportAt = null; // try again with the next fix
      return;
    } finally {
      _backendReporting = false;
    }
    // Confirmed while this report was on its way: send it now, not with the
    // next regular report minutes later.
    if (_pendingHqAcks.isNotEmpty) {
      unawaited(_reportToBackend(force: true));
    }
  }

  // --- Messages from the commanders' panel ------------------------------------------

  /// Sender shown for panel messages.
  static const hqSender = 'VELITELSTVÍ';
  int? _lastHqMessageId;

  /// Confirmed priority messages not yet reported to the server.
  final Set<int> _pendingHqAcks = {};

  /// Confirms a priority panel message ("Rozumím"); the confirmation goes
  /// to the server right away, or with the next report when offline.
  void acknowledgeHqMessage(MeshMessage message) {
    final id = message.hqMessageId;
    if (id == null || !message.needsAcknowledgement) {
      return;
    }
    final index = _messages.indexWhere((m) => m.hqMessageId == id);
    if (index == -1) {
      return;
    }
    _messages[index] = _messages[index].copyWith(acknowledgedAt: _clock());
    _pendingHqAcks.add(id);
    _log(
      MissionEventKind.status,
      'Potvrzen rozkaz velitelství: ${message.body}',
    );
    _notify();
    unawaited(_persistState());
    unawaited(_reportToBackend(force: true));
  }

  void _applyHqMessages(List<HqMessage> incoming) {
    var added = false;
    for (final message in incoming) {
      final last = _lastHqMessageId;
      if (last != null && message.id <= last) {
        continue;
      }
      _lastHqMessageId = message.id;
      final group = allowedGroups
          .where((g) => g.id == message.groupId)
          .firstOrNull;
      if (group == null) {
        continue;
      }
      _messages.insert(
        0,
        MeshMessage(
          sender: hqSender,
          body: message.text,
          sentAt: message.at,
          groupId: group.id,
          targetLabel: group.name,
          priority: message.priority,
          viaInternet: true,
          hqMessageId: message.id,
        ),
      );
      _countIncoming(group.id);
      _log(
        MissionEventKind.status,
        'Zpráva z velitelství pro ${group.name}: ${message.text}',
      );
      if (!_appInForeground) {
        unawaited(
          _carBridge.notifyMessage(
            groupId: group.id,
            groupName: group.name,
            sender: hqSender,
            body: message.text,
            sentAt: message.at,
          ),
        );
      }
      added = true;
    }
    if (added) {
      _notify();
      unawaited(_persistState());
    }
  }

  /// Below this speed the GPS course is noise.
  static const _minCourseSpeedMps = 1.5;

  void _applySelfFix(LocationFix fix) {
    final selfIndex = _nodes.indexWhere((node) => node.isSelf);
    if (selfIndex == -1) {
      return;
    }
    final heading = fix.headingDeg;
    final speed = fix.speedMps ?? 0;
    if (heading != null && speed >= _minCourseSpeedMps) {
      _courseDeg = heading % 360;
    }
    // Smoothed so a single GPS spike does not swing the ETA.
    if (speed >= _minCourseSpeedMps) {
      final kmh = speed * 3.6;
      final previous = _speedKmh;
      _speedKmh = previous == null ? kmh : previous * 0.7 + kmh * 0.3;
    } else {
      _speedKmh = null;
    }
    _nodes[selfIndex] = _nodes[selfIndex].copyWith(
      latitude: fix.latitude,
      longitude: fix.longitude,
      altitudeM: fix.altitudeM.round(),
      lastSeenAt: fix.timestamp,
    );
    _replaceNodes(MeshNode.relativeToSelf(_nodes));
    if (_session != null) {
      _mission.record(fix);
      unawaited(_reportToBackend(latest: fix));
    }
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

    // Names arrive even from nodes without a GPS fix; remember them so
    // their messages show the callsign rather than the node number.
    final announced = _eventCallSign(event);
    if (announced != null) {
      _knownNames[nodeNum] = announced;
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
    _countIncoming(group.id);
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
    _log(
      MissionEventKind.waypoint,
      'Nový bod ${waypoint.code} (${waypoint.typeLabel}) ${waypoint.mgrs}',
    );
    _waypoints.add(waypoint);
    _notify();
    unawaited(_persistState());
    return waypoint;
  }

  /// Changes type and note of [waypoint], keeping its code and position
  /// so a re-share replaces it on teammates' maps too.
  TacticalWaypoint updateWaypoint(
    TacticalWaypoint waypoint, {
    required TacticalWaypointType type,
    String note = '',
  }) {
    final updated = TacticalWaypoint(
      code: waypoint.code,
      type: type,
      latitude: waypoint.latitude,
      longitude: waypoint.longitude,
      note: note.trim(),
      priority:
          type == TacticalWaypointType.medevac ||
          type == TacticalWaypointType.danger,
      sharedBy: waypoint.sharedBy,
      createdAt: waypoint.createdAt,
      meshWaypointId: waypoint.meshWaypointId,
    );
    final index = _waypoints.indexOf(waypoint);
    if (index == -1) {
      return waypoint;
    }
    _waypoints[index] = updated;
    _notify();
    unawaited(_persistState());
    return updated;
  }

  // --- Rendezvous ------------------------------------------------------------------

  Rendezvous? _rendezvous;

  /// The current meeting, until half an hour after its time.
  Rendezvous? get rendezvous {
    final meeting = _rendezvous;
    return meeting == null || meeting.isOverAt(_clock()) ? null : meeting;
  }

  /// Live solution to the meeting point; null when the point is unknown
  /// here.
  TacticalNavSolution? get rendezvousSolution {
    final meeting = rendezvous;
    return meeting == null
        ? null
        : NavTarget.waypoint(
            meeting.code,
          ).resolve(self: selfNode, nodes: nodes, waypoints: _waypoints);
  }

  /// Tells the group to meet at [waypoint] at [at].
  Future<void> setRendezvous(TacticalWaypoint waypoint, DateTime at) async {
    if (_session == null) {
      return;
    }
    final meeting = Rendezvous(
      code: waypoint.code,
      at: at,
      setBy: selfNode.callSign,
    );
    _rendezvous = meeting;
    unawaited(_persistState());
    _log(
      MissionEventKind.navigation,
      'Sraz ${meeting.code} v ${meeting.clock}',
    );
    _notify();
    await sendMeshText(
      MeshMessageDraft(text: meeting.shareText, groupId: selectedGroup.id),
    );
  }

  /// Cancels the meeting for everyone.
  Future<void> cancelRendezvous() async {
    final meeting = _rendezvous;
    if (meeting == null) {
      return;
    }
    _rendezvous = null;
    _log(MissionEventKind.navigation, 'Sraz ${meeting.code} zrušen');
    _notify();
    await sendMeshText(
      MeshMessageDraft(
        text: Rendezvous.cancelText(meeting.code),
        groupId: selectedGroup.id,
      ),
    );
  }

  /// Hides a meeting someone else set, here only.
  void dismissRendezvous() {
    unawaited(Future(_persistState));
    _rendezvous = null;
    _notify();
  }

  // --- Base ------------------------------------------------------------------------

  String? _baseCode;

  /// The point this user marked as their base (kept on this device only).
  TacticalWaypoint? get baseWaypoint {
    final code = _baseCode;
    return code == null
        ? null
        : _waypoints.where((w) => w.code == code).firstOrNull;
  }

  /// Marks [waypoint] as the base; null clears it.
  void setBase(TacticalWaypoint? waypoint) {
    final session = _session;
    if (session == null || waypoint?.code == _baseCode) {
      return;
    }
    _baseCode = waypoint?.code;
    unawaited(settings.setBaseFor(session.userName, _baseCode));
    if (waypoint != null) {
      _log(MissionEventKind.navigation, 'Základna: ${waypoint.code}');
    }
    _notify();
  }

  /// Starts navigation to the base; false when none is set.
  bool navigateToBase() {
    final base = baseWaypoint;
    if (base == null) {
      return false;
    }
    navigateTo(NavTarget.waypoint(base.code));
    return true;
  }

  /// Received points older than [TacticalWaypoint.oldAfter].
  List<TacticalWaypoint> get oldReceivedWaypoints {
    final now = _clock();
    return [
      for (final waypoint in _waypoints)
        if (waypoint.isOldReceivedAt(now)) waypoint,
    ];
  }

  /// Deletes [oldReceivedWaypoints]; returns how many went.
  int clearOldReceivedWaypoints() {
    final old = oldReceivedWaypoints.toSet();
    if (old.isEmpty) {
      return 0;
    }
    _waypoints.removeWhere(old.contains);
    _log(
      MissionEventKind.waypoint,
      'Smazány staré přijaté body (počet: ${old.length})',
    );
    _notify();
    unawaited(_persistState());
    return old.length;
  }

  void removeWaypoint(TacticalWaypoint waypoint) {
    final removed = _waypoints.remove(waypoint);
    if (removed) {
      _log(MissionEventKind.waypoint, 'Smazán bod ${waypoint.code}');
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
    final meeting = Rendezvous.parse(text, now: _clock());
    if (meeting != null) {
      if (meeting.setBy != selfNode.callSign) {
        _rendezvous = meeting;
        _log(
          MissionEventKind.navigation,
          'Sraz ${meeting.code} v ${meeting.clock} (${meeting.setBy})',
        );
      }
      return;
    }
    final cancelled = Rendezvous.parseCancel(text);
    if (cancelled != null) {
      if (_rendezvous?.code == cancelled) {
        _rendezvous = null;
        _log(MissionEventKind.navigation, 'Sraz $cancelled zrušen ($sender)');
      }
      return;
    }
    final status = MemberStatus.parse(text);
    if (status != null) {
      if (status.callSign != selfNode.callSign) {
        _statuses.report(status.callSign, status.status, now);
        _log(
          MissionEventKind.status,
          '${status.callSign}: ${status.status.label}',
        );
      }
      return;
    }
    final sos = SosSignal.parse(text);
    if (sos != null) {
      // Our own outgoing calls are shown by the "SOS AKTIVNÍ" banner.
      if (sender != selfNode.callSign) {
        _logSos(sos, sender);
        _sos.apply(sos, sender: sender, at: now);
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
      _log(
        MissionEventKind.waypoint,
        'Bod ${shared.code} (${shared.typeLabel}) od $sender',
      );
      return;
    }
    final contact = ContactReport.parse(text);
    if (contact != null) {
      _log(
        MissionEventKind.waypoint,
        'CONTACT od $sender: ${contact.contactType} ${contact.size}',
      );
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

  /// Our own distress call is being repeated.
  bool get sosActive => _sos.active;

  /// Teammates' calls not yet acknowledged here and repeated within the
  /// last 30 minutes, newest first.
  List<SosAlert> get activeSosAlerts => _sos.alerts;

  /// Starts repeating a distress call with the current position every
  /// [sosRepeat] until [stopSos].
  Future<void> startSos() async {
    if (_session == null) {
      return;
    }
    if (!_sos.active) {
      _log(MissionEventKind.sos, 'SOS vyhlášeno (${selfNode.mgrs})');
    }
    await _sos.start();
  }

  Future<void> stopSos() async {
    if (_sos.active) {
      _log(MissionEventKind.sos, 'SOS zrušeno');
    }
    await _sos.stop();
  }

  /// Logs the first call of an SOS series (they repeat every minute), its
  /// cancellation and answers.
  void _logSos(SosSignal signal, String sender) {
    switch (signal) {
      case SosCall(:final callSign, :final mgrs):
        final name = callSign ?? sender;
        if (!_sos.hasCall(name)) {
          _log(
            MissionEventKind.sos,
            'SOS od $name${mgrs == null ? '' : ' ($mgrs)'}',
          );
        }
      case SosCancel(:final callSign):
        _log(MissionEventKind.sos, '$callSign zrušil SOS');
      case SosAck(:final from, :final to):
        _log(MissionEventKind.sos, '$from: beru SOS $to');
    }
  }

  /// "Beru": tells the caller help is on it and hides the banner here.
  Future<void> acknowledgeSos(SosAlert alert) {
    _log(MissionEventKind.sos, 'Beru SOS ${alert.callSign}');
    return _sos.acknowledge(alert);
  }

  Future<void> _sendSosCall() async {
    if (_session == null) {
      return;
    }
    final self = selfNode;
    unawaited(_shareInternetPosition(force: true));
    await _sendPriority(
      SosSignal.call(
        callSign: self.callSign,
        mgrs: self.mgrs,
        latitude: self.latitude,
        longitude: self.longitude,
      ),
    );
  }

  Future<void> _sendPriority(String text) => sendMeshText(
    MeshMessageDraft(text: text, groupId: selectedGroup.id, priority: true),
  );

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
      final restoredEvents = [
        for (final json in snapshot.events ?? const <Map<String, dynamic>>[])
          ?MissionEvent.fromJson(json),
      ];
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
        _mission.replace(restoredTrack);
      }
      // Events logged since this login are newer than the snapshot.
      _missionLog.appendRestored(restoredEvents);
      _restoreExtras(snapshot.extras);
      _notify();
      final liveFix = _locationState.lastFix;
      if (liveFix != null) {
        _applySelfFix(liveFix);
      }
    } catch (_) {
      // Ignore corrupt or incompatible local state and keep demo defaults.
    }
  }

  /// Navigation target, rendezvous and statuses from the last session,
  /// unless something newer happened since login or they are stale.
  void _restoreExtras(Map<String, dynamic>? extras) {
    if (extras == null) {
      return;
    }
    Map<String, dynamic>? map(Object? value) => value is Map
        ? value.map((key, value) => MapEntry(key.toString(), value))
        : null;
    final target = map(extras['navTarget']);
    if (_navTarget == null && target != null) {
      final restored = NavTarget.fromJson(target);
      if (restored?.resolve(
            self: selfNode,
            nodes: nodes,
            waypoints: _waypoints,
          ) !=
          null) {
        _navTarget = restored;
      }
    }
    final meeting = map(extras['rendezvous']);
    if (_rendezvous == null && meeting != null) {
      final restored = Rendezvous.fromJson(meeting);
      if (restored != null && !restored.isOverAt(_clock())) {
        _rendezvous = restored;
      }
    }
    final statuses = map(extras['statuses']);
    if (statuses != null) {
      _statuses.restore(statuses);
    }
    final hqMessageId = extras['hqMessageId'];
    if (hqMessageId is int &&
        (_lastHqMessageId == null || hqMessageId > _lastHqMessageId!)) {
      _lastHqMessageId = hqMessageId;
    }
    final acks = extras['hqAcks'];
    if (acks is List) {
      _pendingHqAcks.addAll(acks.whereType<int>());
    }
    final sos = map(extras['sos']);
    if (sos != null && _sos.restore(sos, now: _clock()) && !_sos.active) {
      // The app was killed or the phone restarted during our own distress
      // call; whoever needed it may not be able to start it again.
      _log(MissionEventKind.sos, 'SOS obnoveno po restartu');
      _notice('SOS obnoveno po restartu – výzva se dál opakuje.');
      unawaited(_sos.start());
    }
  }

  Future<void>? _saving;
  bool _saveAgain = false;

  /// Saves the state, one save at a time: requests arriving during a save
  /// are merged into one more save with the newest state. The returned
  /// future completes once that state is written.
  Future<void> _persistState() {
    _saveAgain = true;
    return _saving ??= _saveLoop();
  }

  Future<void> _saveLoop() async {
    try {
      while (_saveAgain) {
        _saveAgain = false;
        await _saveSnapshot();
      }
    } finally {
      _saving = null;
    }
  }

  Future<void> _saveSnapshot() async {
    final session = _session;
    if (session == null) {
      return;
    }
    try {
      await _stateStore.save(
        nodes: [
          for (final node in _nodes)
            if (_isCurrent(node)) node.toJson(),
        ],
        messages: [for (final message in _messages.take(150)) message.toJson()],
        waypoints: [for (final waypoint in _waypoints) waypoint.toJson()],
        track: _mission.toJson(),
        events: _missionLog.toJson(),
        extras: {
          'navTarget': ?_navTarget?.toJson(),
          'rendezvous': ?_rendezvous?.toJson(),
          'statuses': _statuses.toJson(),
          'sos': _sos.toJson(),
          'hqMessageId': ?_lastHqMessageId,
          if (_pendingHqAcks.isNotEmpty) 'hqAcks': _pendingHqAcks.toList(),
        },
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
      _checkDangers();
      _checkNavTarget();
      if (_session != null) {
        _peerTrails.update(nodes);
        for (final lost in _contactWatch.update(nodes)) {
          _log(MissionEventKind.contact, 'Ztráta spojení: ${lost.callSign}');
        }
        for (final node in _batteryWatch.update(nodes)) {
          final who = node.isSelf ? 'Můj T-Beam' : node.callSign;
          _log(
            MissionEventKind.contact,
            '$who: slabá baterie ${node.batteryPercent} %',
          );
          _notice('$who: slabá baterie ${node.batteryPercent} %');
        }
      }
      _syncCarTargets();
      notifyListeners();
    }
  }

  void _notice(String message) {
    if (!_noticeController.isClosed) {
      _noticeController.add(message);
    }
  }

  /// Callsigns announced by nodes, including ones without a position yet.
  final Map<int, String> _knownNames = {};

  String? _nodeCallSign(int? nodeNum) {
    if (nodeNum == null) {
      return null;
    }
    for (final node in _nodes) {
      if (node.nodeNum == nodeNum) {
        return node.callSign;
      }
    }
    return _knownNames[nodeNum];
  }

  String _nodeHex(int? nodeNum) {
    if (nodeNum == null) {
      return '!UNKNOWN';
    }
    return '!${nodeNum.toRadixString(16).padLeft(8, '0').toUpperCase()}';
  }
}
