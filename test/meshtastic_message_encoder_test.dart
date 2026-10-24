import 'package:flutter_test/flutter_test.dart';
import 'package:tactical_car_app/services/meshtastic_message_encoder.dart';
import 'package:tactical_car_app/services/protobuf_wire_writer.dart';
import 'package:tactical_car_app/services/meshtastic_packet_decoder.dart';

void main() {
  test('encodes group text as ToRadio broadcast packet', () {
    const encoder = MeshtasticMessageEncoder();

    final bytes = encoder.encodeGroupText(text: 'OK', channelIndex: 2);

    expect(bytes, [
      0x0A,
      0x0F,
      0x15,
      0xFF,
      0xFF,
      0xFF,
      0xFF,
      0x18,
      0x02,
      0x22,
      0x06,
      0x08,
      0x01,
      0x12,
      0x02,
      0x4F,
      0x4B,
    ]);
  });

  test('encodes direct text with destination and ack request', () {
    const encoder = MeshtasticMessageEncoder();

    final bytes = encoder.encodeDirectText(
      text: 'DM',
      destinationNode: 0xA1100002,
      channelIndex: 1,
    );

    expect(bytes, [
      0x0A,
      0x11,
      0x15,
      0x02,
      0x00,
      0x10,
      0xA1,
      0x18,
      0x01,
      0x22,
      0x06,
      0x08,
      0x01,
      0x12,
      0x02,
      0x44,
      0x4D,
      0x50,
      0x01,
    ]);
  });

  test('encodes want_config_id request', () {
    const encoder = MeshtasticMessageEncoder();

    // ToRadio field 3 (varint) = 0x12345678
    expect(encoder.encodeWantConfig(0x12345678), [
      0x18,
      0xF8,
      0xAC,
      0xD1,
      0x91,
      0x01,
    ]);
  });

  test('writes client packet id when given', () {
    const encoder = MeshtasticMessageEncoder();

    final withId = encoder.encodeGroupText(
      text: 'OK',
      channelIndex: 2,
      packetId: 0x01020304,
    );
    final withoutId = encoder.encodeGroupText(text: 'OK', channelIndex: 2);

    // MeshPacket grows by key 0x35 + 4 bytes little-endian id.
    expect(withId.length, withoutId.length + 5);
    expect(withId.sublist(withId.length - 5), [0x35, 0x04, 0x03, 0x02, 0x01]);
  });

  test('encodes phone position that the decoder reads back', () {
    const encoder = MeshtasticMessageEncoder();
    final toRadio = encoder.encodePosition(
      latitude: 50.0875123,
      longitude: -14.4206711,
      altitudeM: -12,
      time: DateTime.utc(2026, 10, 24, 12),
      packetId: 0x0A0B0C0D,
    );

    // Unwrap ToRadio.packet and decode it as a received FromRadio.packet.
    final fromRadio = [0x12, ...toRadio.sublist(1)];
    final event = const MeshtasticPacketDecoder()
        .decodeFromRadio(fromRadio)
        .single;
    expect(event.type, DecodedMeshEventType.position);
    expect(event.to, meshtasticBroadcastNode);
    expect(event.channelIndex, 0);
    expect(event.packetId, 0x0A0B0C0D);
    expect(event.latitude, closeTo(50.0875123, 1e-7));
    expect(event.longitude, closeTo(-14.4206711, 1e-7));
    expect(event.altitude, -12);
  });

  test('negative varints use 10-byte two\'s complement', () {
    final writer = ProtobufWireWriter()..writeVarint(3, -1);
    expect(writer.bytes, [
      0x18,
      0xFF,
      0xFF,
      0xFF,
      0xFF,
      0xFF,
      0xFF,
      0xFF,
      0xFF,
      0xFF,
      0x01,
    ]);
  });
}
