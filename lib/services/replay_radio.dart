import 'dart:async';

import 'mesh_radio.dart';
import 'meshtastic_ble_service.dart';
import 'packet_recording.dart';

/// Plays a [PacketRecording] as if it came from a T-Beam. [speed] scales
/// the recorded timing (0 = everything immediately). Writes are kept in
/// [written] instead of being transmitted.
class ReplayRadio implements MeshRadio {
  ReplayRadio(this.recording, {this.speed = 1});

  final PacketRecording recording;
  final double speed;
  final List<List<int>> written = [];
  final StreamController<MeshtasticBleState> _stateController =
      StreamController.broadcast();
  final StreamController<MeshtasticBlePacket> _packetController =
      StreamController.broadcast();
  MeshtasticBleState _state = MeshtasticBleState.idle;
  int _run = 0;

  /// Completes when the current playback has emitted every packet.
  Future<void> get done => _done.future;
  Completer<void> _done = Completer<void>();

  @override
  Stream<MeshtasticBleState> get stateStream => _stateController.stream;

  @override
  Stream<MeshtasticBlePacket> get packets => _packetController.stream;

  @override
  MeshtasticBleState get state => _state;

  @override
  Future<void> startAutoConnect() async {
    final run = ++_run;
    _done = Completer<void>();
    _setState(
      const MeshtasticBleState(
        status: MeshtasticBleStatus.connected,
        deviceName: 'Replay',
      ),
    );
    var elapsed = Duration.zero;
    for (final packet in recording.packets) {
      if (speed > 0) {
        final wait = (packet.offset - elapsed) * (1 / speed);
        if (wait > Duration.zero) {
          await Future<void>.delayed(wait);
        }
        elapsed = packet.offset;
      } else {
        await Future<void>.delayed(Duration.zero);
      }
      if (run != _run || _packetController.isClosed) {
        return;
      }
      _packetController.add(
        MeshtasticBlePacket(bytes: packet.bytes, receivedAt: DateTime.now()),
      );
    }
    if (!_done.isCompleted) {
      _done.complete();
    }
  }

  @override
  Future<void> disconnect() async {
    _run++;
    _setState(
      const MeshtasticBleState(status: MeshtasticBleStatus.disconnected),
    );
  }

  @override
  Future<void> writeToRadio(List<int> protobufBytes) async {
    if (_state.status != MeshtasticBleStatus.connected) {
      throw StateError('Replay radio is not connected.');
    }
    written.add(protobufBytes);
  }

  @override
  Future<void> dispose() async {
    _run++;
    await _stateController.close();
    await _packetController.close();
  }

  void _setState(MeshtasticBleState value) {
    _state = value;
    if (!_stateController.isClosed) {
      _stateController.add(value);
    }
  }
}
