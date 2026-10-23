import 'dart:async';

import 'package:tactical_car_app/services/location_service.dart';
import 'package:tactical_car_app/services/meshtastic_ble_service.dart';

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
