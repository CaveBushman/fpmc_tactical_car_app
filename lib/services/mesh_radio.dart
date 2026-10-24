import 'meshtastic_ble_service.dart';

/// A Meshtastic radio link: the BLE T-Beam in production, a replay of a
/// recorded session in tests and demos.
abstract class MeshRadio {
  Stream<MeshtasticBleState> get stateStream;

  /// Raw FromRadio protobuf frames.
  Stream<MeshtasticBlePacket> get packets;
  MeshtasticBleState get state;

  Future<void> startAutoConnect();
  Future<void> disconnect();

  /// Raw ToRadio protobuf frame; throws when not connected.
  Future<void> writeToRadio(List<int> protobufBytes);
  Future<void> dispose();
}
