import 'dart:convert';

import 'meshtastic_packet_decoder.dart';
import 'protobuf_wire_writer.dart';

const meshtasticBroadcastNode = 0xFFFFFFFF;

class MeshtasticMessageEncoder {
  const MeshtasticMessageEncoder();

  List<int> encodeGroupText({required String text, required int channelIndex}) {
    return _encodeTextPacket(
      text: text,
      destinationNode: meshtasticBroadcastNode,
      channelIndex: channelIndex,
      wantAck: false,
    );
  }

  List<int> encodeDirectText({
    required String text,
    required int destinationNode,
    required int channelIndex,
  }) {
    return _encodeTextPacket(
      text: text,
      destinationNode: destinationNode,
      channelIndex: channelIndex,
      wantAck: true,
    );
  }

  List<int> _encodeTextPacket({
    required String text,
    required int destinationNode,
    required int channelIndex,
    required bool wantAck,
  }) {
    final data = ProtobufWireWriter()
      ..writeVarint(1, MeshtasticPacketDecoder.textMessageApp)
      ..writeBytes(2, utf8.encode(text));

    final packet = ProtobufWireWriter()
      ..writeFixed32(2, destinationNode)
      ..writeVarint(3, channelIndex)
      ..writeMessage(4, data);

    if (wantAck) {
      packet.writeBool(10, true);
    }

    final toRadio = ProtobufWireWriter()..writeMessage(1, packet);
    return toRadio.bytes;
  }
}
