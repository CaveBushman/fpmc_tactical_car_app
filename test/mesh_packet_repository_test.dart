import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tactical_car_app/services/mesh_packet_repository.dart';
import 'package:tactical_car_app/services/meshtastic_packet_decoder.dart';
import 'package:tactical_car_app/services/meshtastic_ble_service.dart';

void main() {
  test('tracks raw Meshtastic packet diagnostics', () async {
    final repository = MeshPacketRepository();
    final packet = MeshtasticBlePacket(
      bytes: [0, 1, 2, 10, 15, 16, 255],
      receivedAt: DateTime(2026, 6, 3, 12, 34, 56),
    );

    repository.ingest(packet);

    expect(repository.diagnostics.packetCount, 1);
    expect(repository.diagnostics.lastPacketSize, 7);
    expect(repository.diagnostics.lastPacketHex, '00 01 02 0A 0F 10 FF');
    expect(repository.diagnostics.decodedEventCount, 0);

    await repository.dispose();
  });

  test('decodes FromRadio NodeInfo diagnostics', () async {
    final repository = MeshPacketRepository();
    final eventsFuture = repository.eventsStream.first;
    final packet = MeshtasticBlePacket(
      bytes: _message(4, [
        ..._varint(1, 0x1234ABCD),
        ..._message(2, [..._string(2, 'RAVEN-2'), ..._string(3, 'R2')]),
        ..._message(3, [
          ..._fixed32(1, 500875000),
          ..._fixed32(2, 144208000),
          ..._varint(3, 291),
        ]),
      ]),
      receivedAt: DateTime(2026, 6, 3, 12, 34, 56),
    );

    repository.ingest(packet);
    final events = await eventsFuture;

    expect(repository.diagnostics.decodedEventCount, 1);
    expect(
      repository.diagnostics.lastDecodedEvent?.type,
      DecodedMeshEventType.nodeInfo,
    );
    expect(repository.diagnostics.lastDecodedEvent?.longName, 'RAVEN-2');
    expect(repository.diagnostics.lastDecodedEvent?.shortName, 'R2');
    expect(
      repository.diagnostics.lastDecodedEvent?.latitude,
      closeTo(50.0875, 0.000001),
    );
    expect(
      repository.diagnostics.lastDecodedEvent?.longitude,
      closeTo(14.4208, 0.000001),
    );
    expect(repository.diagnostics.lastDecodedEvent?.altitude, 291);
    expect(events, hasLength(1));
    expect(events.single.nodeNum, 0x1234ABCD);

    await repository.dispose();
  });

  test('decodes FromRadio text MeshPacket', () {
    const decoder = MeshtasticPacketDecoder();
    final bytes = _message(2, [
      ..._fixed32(1, 0x1234ABCD),
      ..._fixed32(2, 0xFFFFFFFF),
      ..._varint(3, 2),
      ..._message(4, [
        ..._varint(1, MeshtasticPacketDecoder.textMessageApp),
        ..._bytes(2, utf8.encode('Na pozici')),
      ]),
      ..._fixed32(6, 0x00000042),
    ]);

    final events = decoder.decodeFromRadio(bytes);

    expect(events, hasLength(1));
    expect(events.single.type, DecodedMeshEventType.textMessage);
    expect(events.single.from, 0x1234ABCD);
    expect(events.single.channelIndex, 2);
    expect(events.single.text, 'Na pozici');
    expect(events.single.packetId, 0x00000042);
  });
}

List<int> _message(int field, List<int> value) => _bytes(field, value);

List<int> _string(int field, String value) => _bytes(field, utf8.encode(value));

List<int> _bytes(int field, List<int> value) => [
  ..._key(field, 2),
  ..._rawVarint(value.length),
  ...value,
];

List<int> _varint(int field, int value) => [
  ..._key(field, 0),
  ..._rawVarint(value),
];

List<int> _fixed32(int field, int value) {
  final unsigned = value & 0xFFFFFFFF;
  return [
    ..._key(field, 5),
    unsigned & 0xFF,
    (unsigned >> 8) & 0xFF,
    (unsigned >> 16) & 0xFF,
    (unsigned >> 24) & 0xFF,
  ];
}

List<int> _key(int field, int wireType) => _rawVarint((field << 3) | wireType);

List<int> _rawVarint(int value) {
  final bytes = <int>[];
  var remaining = value;
  while (remaining >= 0x80) {
    bytes.add((remaining & 0x7F) | 0x80);
    remaining >>= 7;
  }
  bytes.add(remaining);
  return bytes;
}
