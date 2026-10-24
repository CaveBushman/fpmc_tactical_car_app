import 'dart:async';

import '../models/navigation.dart';
import '../models/sos.dart';

/// Own distress call (repeated until cancelled) and teammates' calls.
/// Sending and map changes go through the callbacks, so this holds only
/// the SOS state and timing.
class SosCoordinator {
  SosCoordinator({
    required this.repeat,
    required this.sendCall,
    required this.sendCancel,
    required this.sendAck,
    required this.upsertPoint,
    required this.removePoint,
    required this.onChanged,
  });

  static const alertLifetime = Duration(minutes: 30);

  final Duration repeat;

  /// Sends the call with the current position.
  final Future<void> Function() sendCall;
  final Future<void> Function() sendCancel;

  /// Sends "SOS PŘIJATO" to the given callsign.
  final Future<void> Function(String callSign) sendAck;
  final void Function(TacticalWaypoint point) upsertPoint;
  final void Function(String code) removePoint;
  final void Function() onChanged;

  bool _active = false;
  Timer? _timer;
  final Map<String, SosAlert> _alerts = {};

  bool get active => _active;

  /// Unacknowledged calls repeated within [alertLifetime], newest first.
  List<SosAlert> get alerts {
    final cutoff = DateTime.now().subtract(alertLifetime);
    return _alerts.values
        .where((alert) => !alert.acknowledged && alert.lastAt.isAfter(cutoff))
        .toList()
      ..sort((a, b) => b.lastAt.compareTo(a.lastAt));
  }

  Future<void> start() async {
    if (_active) {
      return;
    }
    _active = true;
    onChanged();
    _timer = Timer.periodic(repeat, (_) => unawaited(_repeatCall()));
    await sendCall();
  }

  Future<void> _repeatCall() async {
    if (_active) {
      await sendCall();
    }
  }

  Future<void> stop() async {
    if (!_active) {
      return;
    }
    _timer?.cancel();
    _active = false;
    onChanged();
    await sendCancel();
  }

  /// "Beru": answers the caller and hides the banner here.
  Future<void> acknowledge(SosAlert alert) async {
    final current = _alerts[alert.callSign];
    if (current == null) {
      return;
    }
    _alerts[alert.callSign] = current.copyWith(acknowledged: true);
    onChanged();
    await sendAck(alert.callSign);
  }

  /// A signal received from [sender] (not our own messages).
  void apply(SosSignal signal, {required String sender, required DateTime at}) {
    switch (signal) {
      case SosCall(
        :final callSign,
        :final mgrs,
        :final latitude,
        :final longitude,
      ):
        final name = callSign ?? sender;
        final previous = _alerts[name];
        _alerts[name] = SosAlert(
          callSign: name,
          lastAt: at,
          mgrs: mgrs ?? previous?.mgrs,
          latitude: latitude ?? previous?.latitude,
          longitude: longitude ?? previous?.longitude,
          // A repeated call after "Beru" stays acknowledged.
          acknowledged: previous?.acknowledged ?? false,
        );
        if (latitude != null && longitude != null) {
          upsertPoint(
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
        _alerts.remove(callSign);
        removePoint('SOS-$callSign');
      case SosAck():
        break; // shown as a normal message
    }
  }

  /// Logout/wipe: stop without sending anything and forget all calls.
  void reset() {
    _timer?.cancel();
    _active = false;
    _alerts.clear();
  }

  void dispose() => _timer?.cancel();

  static String _clock(DateTime at) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(at.hour)}:${two(at.minute)}';
  }
}
