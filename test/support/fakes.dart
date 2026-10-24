import 'dart:async';
import 'dart:convert';

import 'package:tactical_car_app/services/backend_client.dart';
import 'package:tactical_car_app/services/location_service.dart';
import 'package:tactical_car_app/services/meshtastic_ble_service.dart';
import 'package:tactical_car_app/services/ptt/voice_transport.dart';

class FakeLocationService implements LocationService {
  final StreamController<LocationState> _stateController =
      StreamController.broadcast();
  final StreamController<LocationFix> _fixController =
      StreamController.broadcast();
  LocationState _state = LocationState.idle;
  int startCount = 0;

  @override
  Stream<LocationState> get stateStream => _stateController.stream;

  @override
  Stream<LocationFix> get fixes => _fixController.stream;

  @override
  LocationState get state => _state;

  void emit(LocationFix fix) {
    _state = LocationState(status: LocationStatus.active, lastFix: fix);
    _stateController.add(_state);
    _fixController.add(fix);
  }

  @override
  Future<void> start() async {
    startCount++;
    _state = const LocationState(status: LocationStatus.searching);
    _stateController.add(_state);
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> openSettings() async {}

  @override
  Future<void> dispose() async {
    await _stateController.close();
    await _fixController.close();
  }
}

class FakeBleService extends MeshtasticBleService {
  bool connected = true;
  final List<List<int>> written = [];

  @override
  Future<void> writeToRadio(List<int> protobufBytes) async {
    if (!connected) {
      throw StateError('not connected');
    }
    written.add(protobufBytes);
  }
}

class FakeVoiceTransport implements VoiceTransport {
  final StreamController<VoiceEvent> _events = StreamController.broadcast();
  PttJoinInfo? connectedWith;
  bool microphoneEnabled = false;
  bool disposed = false;
  Object? connectError;
  final List<Map<String, dynamic>> sent = [];

  @override
  Stream<VoiceEvent> get events => _events.stream;

  void emit(VoiceEvent event) => _events.add(event);

  /// Floor message as another member would send it.
  void remoteFloor(String from, String op, DateTime at) => emit(
    VoiceDataReceived(
      from: from,
      data: utf8.encode(
        jsonEncode({'op': op, 'at': at.toUtc().toIso8601String()}),
      ),
    ),
  );

  @override
  Future<void> connect(PttJoinInfo info) async {
    if (connectError != null) {
      throw connectError!;
    }
    connectedWith = info;
  }

  @override
  Future<void> setMicrophoneEnabled(bool enabled) async {
    microphoneEnabled = enabled;
  }

  @override
  Future<void> sendData(List<int> data) async {
    sent.add(jsonDecode(utf8.decode(data)) as Map<String, dynamic>);
  }

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> dispose() async {
    disposed = true;
    await _events.close();
  }
}

PttJoinInfo fakeJoinInfo({String identity = 'operator', int keyId = 3}) =>
    PttJoinInfo(
      liveKitUrl: 'wss://ptt.example.test',
      room: 'ptt-alpha',
      identity: identity,
      token: 'lk-token',
      keys: [
        GroupKeyMaterial(id: keyId - 1, bytes: List.filled(32, 1)),
        GroupKeyMaterial(id: keyId, bytes: List.filled(32, 2)),
      ],
    );
