import 'dart:convert';

import 'meshtastic_packet_decoder.dart';
import 'protobuf_wire_writer.dart';

const meshtasticBroadcastNode = 0xFFFFFFFF;

class MeshtasticMessageEncoder {
  const MeshtasticMessageEncoder();

  /// ToRadio.want_config_id: asks the radio to stream MyNodeInfo, the node
  /// DB and config, terminated by FromRadio.config_complete_id == [configId].
  List<int> encodeWantConfig(int configId) {
    return (ProtobufWireWriter()..writeVarint(3, configId & 0xFFFFFFFF)).bytes;
  }

  List<int> encodeGroupText({
    required String text,
    required int channelIndex,
    int? packetId,
  }) {
    return _encodeTextPacket(
      text: text,
      destinationNode: meshtasticBroadcastNode,
      channelIndex: channelIndex,
      wantAck: false,
      packetId: packetId,
    );
  }

  /// Own position from the phone GPS as a broadcast POSITION_APP packet on
  /// the primary channel (what the official apps send when the radio has
  /// no GPS fix of its own).
  List<int> encodePosition({
    required double latitude,
    required double longitude,
    required int altitudeM,
    required DateTime time,
    int? packetId,
  }) {
    final position = ProtobufWireWriter()
      ..writeFixed32(1, (latitude * 1e7).round())
      ..writeFixed32(2, (longitude * 1e7).round())
      ..writeVarint(3, altitudeM)
      ..writeFixed32(4, time.toUtc().millisecondsSinceEpoch ~/ 1000);
    final data = ProtobufWireWriter()
      ..writeVarint(1, MeshtasticPacketDecoder.positionApp)
      ..writeMessage(2, position);
    final packet = ProtobufWireWriter()
      ..writeFixed32(2, meshtasticBroadcastNode)
      ..writeVarint(3, 0)
      ..writeMessage(4, data);
    if (packetId != null) {
      packet.writeFixed32(6, packetId);
    }
    return (ProtobufWireWriter()..writeMessage(1, packet)).bytes;
  }

  List<int> encodeDirectText({
    required String text,
    required int destinationNode,
    required int channelIndex,
    int? packetId,
  }) {
    return _encodeTextPacket(
      text: text,
      destinationNode: destinationNode,
      channelIndex: channelIndex,
      wantAck: true,
      packetId: packetId,
    );
  }

  List<int> _encodeTextPacket({
    required String text,
    required int destinationNode,
    required int channelIndex,
    required bool wantAck,
    int? packetId,
  }) {
    final data = ProtobufWireWriter()
      ..writeVarint(1, MeshtasticPacketDecoder.textMessageApp)
      ..writeBytes(2, utf8.encode(text));

    final packet = ProtobufWireWriter()
      ..writeFixed32(2, destinationNode)
      ..writeVarint(3, channelIndex)
      ..writeMessage(4, data);

    // A client-chosen id lets the routing ACK/NAK (Data.request_id) be
    // matched back to this message.
    if (packetId != null) {
      packet.writeFixed32(6, packetId);
    }
    if (wantAck) {
      packet.writeBool(10, true);
    }

    final toRadio = ProtobufWireWriter()..writeMessage(1, packet);
    return toRadio.bytes;
  }
}
