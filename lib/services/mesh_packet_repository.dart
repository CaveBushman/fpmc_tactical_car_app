import 'dart:async';

import 'meshtastic_packet_decoder.dart';
import 'meshtastic_ble_service.dart';

class MeshPacketDiagnostics {
  const MeshPacketDiagnostics({
    required this.packetCount,
    this.decodedEventCount = 0,
    this.lastPacketAt,
    this.lastPacketSize = 0,
    this.lastPacketHex = '',
    this.lastDecodedEvent,
  });

  final int packetCount;
  final int decodedEventCount;
  final DateTime? lastPacketAt;
  final int lastPacketSize;
  final String lastPacketHex;
  final DecodedMeshEvent? lastDecodedEvent;

  static const empty = MeshPacketDiagnostics(packetCount: 0);
}

class MeshPacketRepository {
  MeshPacketRepository({MeshtasticPacketDecoder? decoder})
    : _decoder = decoder ?? const MeshtasticPacketDecoder();

  final MeshtasticPacketDecoder _decoder;
  final StreamController<MeshPacketDiagnostics> _diagnosticsController =
      StreamController.broadcast();
  final StreamController<List<DecodedMeshEvent>> _eventsController =
      StreamController.broadcast();
  MeshPacketDiagnostics _diagnostics = MeshPacketDiagnostics.empty;

  Stream<MeshPacketDiagnostics> get diagnosticsStream =>
      _diagnosticsController.stream;
  Stream<List<DecodedMeshEvent>> get eventsStream => _eventsController.stream;
  MeshPacketDiagnostics get diagnostics => _diagnostics;

  void ingest(MeshtasticBlePacket packet) {
    final hex = packet.bytes
        .take(16)
        .map((byte) => byte.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join(' ');
    final decodedEvents = _decode(packet.bytes);
    _diagnostics = MeshPacketDiagnostics(
      packetCount: _diagnostics.packetCount + 1,
      decodedEventCount: _diagnostics.decodedEventCount + decodedEvents.length,
      lastPacketAt: packet.receivedAt,
      lastPacketSize: packet.bytes.length,
      lastPacketHex: hex,
      lastDecodedEvent: decodedEvents.isEmpty
          ? _diagnostics.lastDecodedEvent
          : decodedEvents.last,
    );
    _diagnosticsController.add(_diagnostics);
    if (decodedEvents.isNotEmpty) {
      _eventsController.add(decodedEvents);
    }
  }

  List<DecodedMeshEvent> _decode(List<int> bytes) {
    try {
      return _decoder.decodeFromRadio(bytes);
    } on FormatException {
      return const [];
    }
  }

  Future<void> dispose() async {
    await _diagnosticsController.close();
    await _eventsController.close();
  }
}
