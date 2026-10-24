import 'dart:async';

import 'package:geolocator/geolocator.dart';

class LocationFix {
  const LocationFix({
    required this.latitude,
    required this.longitude,
    required this.altitudeM,
    required this.accuracyM,
    required this.timestamp,
    this.headingDeg,
    this.speedMps,
  });

  final double latitude;
  final double longitude;
  final double altitudeM;
  final double accuracyM;
  final DateTime timestamp;
  final double? headingDeg;
  final double? speedMps;
}

enum LocationStatus {
  idle,
  searching,
  active,
  serviceDisabled,
  permissionDenied,
  permissionDeniedForever,
  unavailable,
}

class LocationState {
  const LocationState({required this.status, this.lastFix, this.lastError});

  final LocationStatus status;
  final LocationFix? lastFix;
  final String? lastError;

  static const idle = LocationState(status: LocationStatus.idle);
}

abstract class LocationService {
  Stream<LocationState> get stateStream;
  Stream<LocationFix> get fixes;
  LocationState get state;

  Future<void> start();
  Future<void> stop();

  /// Coarser, sparser fixes to save battery; applied immediately when
  /// running.
  Future<void> setPowerSaving(bool enabled);

  /// Opens the OS location switch or app permission screen, depending on
  /// what currently blocks GPS.
  Future<void> openSettings();
  Future<void> dispose();
}

class GeolocatorLocationService implements LocationService {
  GeolocatorLocationService({
    this.distanceFilterM = 5,
    this.powerSavingDistanceFilterM = 50,
  });

  final int distanceFilterM;
  final int powerSavingDistanceFilterM;
  bool _powerSaving = false;
  final StreamController<LocationState> _stateController =
      StreamController.broadcast();
  final StreamController<LocationFix> _fixController =
      StreamController.broadcast();
  StreamSubscription<Position>? _positionSubscription;
  LocationState _state = LocationState.idle;

  @override
  Stream<LocationState> get stateStream => _stateController.stream;

  @override
  Stream<LocationFix> get fixes => _fixController.stream;

  @override
  LocationState get state => _state;

  @override
  Future<void> start() async {
    await stop();
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _setState(const LocationState(status: LocationStatus.serviceDisabled));
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        _setState(
          const LocationState(status: LocationStatus.permissionDeniedForever),
        );
        return;
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.unableToDetermine) {
        _setState(const LocationState(status: LocationStatus.permissionDenied));
        return;
      }

      _setState(
        LocationState(
          status: LocationStatus.searching,
          lastFix: _state.lastFix,
        ),
      );
      _positionSubscription =
          Geolocator.getPositionStream(
            locationSettings: _powerSaving
                ? LocationSettings(
                    accuracy: LocationAccuracy.medium,
                    distanceFilter: powerSavingDistanceFilterM,
                  )
                : LocationSettings(
                    accuracy: LocationAccuracy.best,
                    distanceFilter: distanceFilterM,
                  ),
          ).listen(
            _onPosition,
            onError: (Object error) {
              _setState(
                LocationState(
                  status: LocationStatus.unavailable,
                  lastFix: _state.lastFix,
                  lastError: error.toString(),
                ),
              );
            },
          );
    } catch (error) {
      // Missing plugin (desktop, tests) or platform failure: keep running
      // without GPS instead of crashing the app.
      _setState(
        LocationState(
          status: LocationStatus.unavailable,
          lastFix: _state.lastFix,
          lastError: error.toString(),
        ),
      );
    }
  }

  @override
  Future<void> stop() async {
    await _positionSubscription?.cancel();
    _positionSubscription = null;
  }

  @override
  Future<void> setPowerSaving(bool enabled) async {
    if (_powerSaving == enabled) {
      return;
    }
    _powerSaving = enabled;
    if (_positionSubscription != null) {
      await start();
    }
  }

  @override
  Future<void> openSettings() async {
    try {
      if (_state.status == LocationStatus.serviceDisabled) {
        await Geolocator.openLocationSettings();
      } else {
        await Geolocator.openAppSettings();
      }
    } catch (error) {
      _setState(
        LocationState(
          status: _state.status,
          lastFix: _state.lastFix,
          lastError: error.toString(),
        ),
      );
    }
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _stateController.close();
    await _fixController.close();
  }

  void _onPosition(Position position) {
    final fix = LocationFix(
      latitude: position.latitude,
      longitude: position.longitude,
      altitudeM: position.altitude,
      accuracyM: position.accuracy,
      timestamp: position.timestamp,
      headingDeg: position.heading >= 0 ? position.heading : null,
      speedMps: position.speed >= 0 ? position.speed : null,
    );
    _fixController.add(fix);
    _setState(LocationState(status: LocationStatus.active, lastFix: fix));
  }

  void _setState(LocationState value) {
    _state = value;
    if (!_stateController.isClosed) {
      _stateController.add(value);
    }
  }
}
