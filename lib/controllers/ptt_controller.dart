import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../services/backend_client.dart';
import '../services/ptt/voice_transport.dart';

enum PttStatus {
  /// Not joined (logged out, or no group).
  offline,
  connecting,

  /// Joined, nobody talking.
  ready,

  /// We hold the floor and the microphone is live.
  transmitting,

  /// Someone else holds the floor.
  receiving,

  /// PTT switched off for this group on the backend.
  disabled,
  error,
}

/// Fetches the join info for a group (backend call in production).
typedef PttJoiner = Future<PttJoinInfo> Function(String groupId);

/// Half-duplex push-to-talk over a [VoiceTransport].
///
/// Floor control: pressing PTT broadcasts `take` with a timestamp and only
/// then opens the microphone; while another member holds the floor PTT is
/// refused. Simultaneous takes are resolved deterministically (earlier
/// timestamp, then lower identity wins) and the loser closes its
/// microphone. A holder that disappears or goes silent past [floorTimeout]
/// loses the floor.
///
/// Without a joiner the controller runs in demo mode: no audio, local
/// state only.
class PttController extends ChangeNotifier {
  PttController({
    this.joiner,
    this._transportFactory,
    DateTime Function()? clock,
    this.floorTimeout = const Duration(seconds: 60),
    this.maxClockSkew = const Duration(seconds: 30),
  }) : _clock = clock ?? DateTime.now;

  final PttJoiner? joiner;
  final VoiceTransport Function()? _transportFactory;
  final DateTime Function() _clock;
  final Duration floorTimeout;

  /// Floor messages further from our clock than this are ignored, so a
  /// recorded message replayed later cannot grab or release the floor.
  final Duration maxClockSkew;

  VoiceTransport? _transport;
  StreamSubscription<VoiceEvent>? _eventsSubscription;
  Timer? _floorTimer;
  int _joinGeneration = 0;
  bool _disposed = false;

  PttStatus _status = PttStatus.offline;
  String _channel = '-';
  String? _identity;
  String? _floorHolder;
  DateTime? _floorTakenAt;
  DateTime? _ourTakeAt;
  int? _keyId;
  String? _error;
  Set<String> _speaking = const {};

  bool get isDemo => joiner == null;
  PttStatus get status => _status;
  String get channel => _channel;
  int? get keyId => _keyId;
  String? get error => _error;

  /// Who is talking now (floor holder, else LiveKit speaker detection).
  String? get speaker =>
      _floorHolder ?? (_speaking.isEmpty ? null : _speaking.first);

  bool get canTransmit =>
      _status == PttStatus.ready || _status == PttStatus.transmitting;

  Future<void> joinGroup(String groupId, String channelLabel) async {
    final generation = ++_joinGeneration;
    await _leaveRoom();
    _channel = channelLabel;
    _error = null;
    _keyId = null;
    final joiner = this.joiner;
    if (joiner == null) {
      _setStatus(PttStatus.ready);
      return;
    }
    _setStatus(PttStatus.connecting);
    try {
      final info = await joiner(groupId);
      if (generation != _joinGeneration || _disposed) {
        return;
      }
      final transport = _transportFactory!();
      _transport = transport;
      _identity = info.identity;
      _eventsSubscription = transport.events.listen(_onEvent);
      await transport.connect(info);
      if (generation != _joinGeneration || _disposed) {
        return;
      }
      _keyId = info.keyId;
      _setStatus(PttStatus.ready);
    } catch (error) {
      if (generation != _joinGeneration || _disposed) {
        return;
      }
      await _leaveRoom();
      _error = _describe(error);
      _setStatus(PttStatus.error);
    }
  }

  /// The selected group has no PTT: leave any room and say why.
  Future<void> disable(String channelLabel) async {
    _joinGeneration++;
    await _leaveRoom();
    _channel = channelLabel;
    _error = 'PTT je pro tuto skupinu vypnuté.';
    _keyId = null;
    _setStatus(PttStatus.disabled);
  }

  Future<void> leave() async {
    _joinGeneration++;
    await _leaveRoom();
    _channel = '-';
    _error = null;
    _setStatus(PttStatus.offline);
  }

  /// Returns false when the floor is taken or PTT is not connected.
  Future<bool> press() async {
    if (_status != PttStatus.ready) {
      return false;
    }
    final at = _clock();
    _ourTakeAt = at;
    _setStatus(PttStatus.transmitting);
    final transport = _transport;
    if (transport == null) {
      return true; // demo
    }
    try {
      await transport.sendData(_floorMessage('take', at));
      if (_status != PttStatus.transmitting) {
        return false; // lost a simultaneous take meanwhile
      }
      await transport.setMicrophoneEnabled(true);
      return true;
    } catch (error) {
      _ourTakeAt = null;
      _error = _describe(error);
      _setStatus(PttStatus.ready);
      return false;
    }
  }

  Future<void> release() async {
    if (_status != PttStatus.transmitting) {
      return;
    }
    _ourTakeAt = null;
    _setStatus(_floorHolder == null ? PttStatus.ready : PttStatus.receiving);
    final transport = _transport;
    if (transport == null) {
      return;
    }
    try {
      await transport.setMicrophoneEnabled(false);
      await transport.sendData(_floorMessage('release', _clock()));
    } catch (_) {
      // Others time the floor out if the release never arrives.
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _joinGeneration++;
    unawaited(_leaveRoom());
    super.dispose();
  }

  void _onEvent(VoiceEvent event) {
    switch (event) {
      case VoiceDataReceived(:final from, :final data):
        _onFloorMessage(from, data);
      case VoiceSpeakersChanged(:final identities):
        _speaking = identities;
        _notify();
      case VoiceParticipantLeft(:final identity):
        if (identity == _floorHolder) {
          _clearFloor();
        }
      case VoiceDisconnected(:final reason):
        _transport = null;
        _floorHolder = null;
        _ourTakeAt = null;
        _error =
            'Spojení s PTT serverem přerušeno${reason == null ? '' : ' ($reason)'}.';
        _setStatus(PttStatus.error);
    }
  }

  void _onFloorMessage(String from, List<int> data) {
    final Map<String, dynamic> message;
    try {
      message = jsonDecode(utf8.decode(data)) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    final at = DateTime.tryParse(message['at']?.toString() ?? '');
    final op = message['op'];
    if (at == null || _clock().difference(at).abs() > maxClockSkew) {
      return;
    }
    if (op == 'take') {
      final ourTake = _ourTakeAt;
      if (_status == PttStatus.transmitting && ourTake != null) {
        final theyWin =
            at.isBefore(ourTake) ||
            (at == ourTake && from.compareTo(_identity ?? '') < 0);
        if (!theyWin) {
          return; // they will yield to us
        }
        _ourTakeAt = null;
        unawaited(_transport?.setMicrophoneEnabled(false));
      }
      _floorHolder = from;
      _floorTakenAt = at;
      _armFloorTimer();
      _setStatus(PttStatus.receiving);
    } else if (op == 'release' && from == _floorHolder) {
      final takenAt = _floorTakenAt;
      if (takenAt != null && at.isBefore(takenAt)) {
        return; // stale release from an earlier transmission
      }
      _clearFloor();
    }
  }

  void _armFloorTimer() {
    _floorTimer?.cancel();
    _floorTimer = Timer(floorTimeout, _clearFloor);
  }

  void _clearFloor() {
    _floorTimer?.cancel();
    _floorHolder = null;
    _floorTakenAt = null;
    if (_status == PttStatus.receiving) {
      _setStatus(PttStatus.ready);
    } else {
      _notify();
    }
  }

  List<int> _floorMessage(String op, DateTime at) =>
      utf8.encode(jsonEncode({'op': op, 'at': at.toUtc().toIso8601String()}));

  Future<void> _leaveRoom() async {
    _floorTimer?.cancel();
    _floorHolder = null;
    _floorTakenAt = null;
    _ourTakeAt = null;
    _speaking = const {};
    await _eventsSubscription?.cancel();
    _eventsSubscription = null;
    final transport = _transport;
    _transport = null;
    if (transport != null) {
      try {
        await transport.dispose();
      } catch (_) {
        // Already gone.
      }
    }
  }

  String _describe(Object error) {
    if (error is BackendException) {
      return switch (error.statusCode) {
        0 => 'Backend nedostupný.',
        401 => 'Relace vypršela, přihlas se znovu.',
        403 => 'Do této skupiny nemáš přístup.',
        _ => 'Backend: ${error.code}',
      };
    }
    return 'PTT: $error';
  }

  void _setStatus(PttStatus status) {
    _status = status;
    _notify();
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }
}
