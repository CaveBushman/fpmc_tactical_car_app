import 'dart:convert';

import 'protobuf_wire_reader.dart';

enum DecodedMeshEventType {
  nodeInfo,
  position,
  textMessage,
  encrypted,
  unknown,
}

class DecodedMeshEvent {
  const DecodedMeshEvent({
    required this.type,
    this.from,
    this.to,
    this.nodeNum,
    this.packetId,
    this.channelIndex,
    this.portNum,
    this.longName,
    this.shortName,
    this.latitude,
    this.longitude,
    this.altitude,
    this.text,
  });

  final DecodedMeshEventType type;
  final int? from;
  final int? to;
  final int? nodeNum;
  final int? packetId;
  final int? channelIndex;
  final int? portNum;
  final String? longName;
  final String? shortName;
  final double? latitude;
  final double? longitude;
  final int? altitude;
  final String? text;

  String get label {
    final name = longName ?? shortName ?? _nodeLabel(nodeNum ?? from);
    switch (type) {
      case DecodedMeshEventType.nodeInfo:
        final position = _positionLabel;
        return position == null
            ? 'NodeInfo $name'
            : 'NodeInfo $name / $position';
      case DecodedMeshEventType.position:
        return 'Pozice $name / ${_positionLabel ?? 'bez souřadnic'}';
      case DecodedMeshEventType.textMessage:
        return 'Zpráva $name: ${text ?? ''}';
      case DecodedMeshEventType.encrypted:
        return 'Šifrovaný MeshPacket ${_nodeLabel(from)}';
      case DecodedMeshEventType.unknown:
        final port = portNum == null ? 'neznámý' : '$portNum';
        return 'Neznámý port $port ${_nodeLabel(from)}';
    }
  }

  String? get _positionLabel {
    final lat = latitude;
    final lon = longitude;
    if (lat == null || lon == null) {
      return null;
    }
    final altitudeLabel = altitude == null ? '' : ' / $altitude m';
    return '${lat.toStringAsFixed(6)}, ${lon.toStringAsFixed(6)}$altitudeLabel';
  }

  static String _nodeLabel(int? node) {
    if (node == null) {
      return 'bez ID';
    }
    return '!${node.toRadixString(16).padLeft(8, '0').toUpperCase()}';
  }
}

class MeshtasticPacketDecoder {
  const MeshtasticPacketDecoder();

  static const textMessageApp = 1;
  static const positionApp = 3;
  static const nodeInfoApp = 4;

  List<DecodedMeshEvent> decodeFromRadio(List<int> bytes) {
    final events = <DecodedMeshEvent>[];
    final reader = ProtobufWireReader(bytes);
    while (!reader.isDone) {
      final field = reader.readField();
      switch (field.number) {
        case 2:
          events.add(_readMeshPacket(reader.readLengthDelimited()));
        case 4:
          events.add(_readNodeInfo(reader.readLengthDelimited()));
        default:
          reader.skipField(field);
      }
    }
    return events;
  }

  DecodedMeshEvent _readMeshPacket(List<int> bytes) {
    final reader = ProtobufWireReader(bytes);
    int? from;
    int? to;
    int? channelIndex;
    int? packetId;
    _DataPayload? data;
    var encrypted = false;

    while (!reader.isDone) {
      final field = reader.readField();
      switch (field.number) {
        case 1:
          from = reader.readFixed32();
        case 2:
          to = reader.readFixed32();
        case 3:
          channelIndex = reader.readVarint();
        case 4:
          data = _readData(reader.readLengthDelimited());
        case 5:
          reader.readLengthDelimited();
          encrypted = true;
        case 6:
          packetId = reader.readFixed32();
        default:
          reader.skipField(field);
      }
    }

    if (encrypted) {
      return DecodedMeshEvent(
        type: DecodedMeshEventType.encrypted,
        from: from,
        to: to,
        packetId: packetId,
        channelIndex: channelIndex,
      );
    }

    final payload = data;
    if (payload == null) {
      return DecodedMeshEvent(
        type: DecodedMeshEventType.unknown,
        from: from,
        to: to,
        packetId: packetId,
        channelIndex: channelIndex,
      );
    }

    switch (payload.portNum) {
      case textMessageApp:
        return DecodedMeshEvent(
          type: DecodedMeshEventType.textMessage,
          from: from,
          to: to,
          packetId: packetId,
          channelIndex: channelIndex,
          portNum: payload.portNum,
          text: utf8.decode(payload.payload, allowMalformed: true),
        );
      case positionApp:
        final position = _readPosition(payload.payload);
        return DecodedMeshEvent(
          type: DecodedMeshEventType.position,
          from: from,
          to: to,
          packetId: packetId,
          channelIndex: channelIndex,
          portNum: payload.portNum,
          latitude: position.latitude,
          longitude: position.longitude,
          altitude: position.altitude,
        );
      case nodeInfoApp:
        final user = _readUser(payload.payload);
        return DecodedMeshEvent(
          type: DecodedMeshEventType.nodeInfo,
          from: from,
          to: to,
          packetId: packetId,
          channelIndex: channelIndex,
          portNum: payload.portNum,
          nodeNum: from,
          longName: user.longName,
          shortName: user.shortName,
        );
      default:
        return DecodedMeshEvent(
          type: DecodedMeshEventType.unknown,
          from: from,
          to: to,
          packetId: packetId,
          channelIndex: channelIndex,
          portNum: payload.portNum,
        );
    }
  }

  _DataPayload _readData(List<int> bytes) {
    final reader = ProtobufWireReader(bytes);
    var portNum = 0;
    var payload = const <int>[];

    while (!reader.isDone) {
      final field = reader.readField();
      switch (field.number) {
        case 1:
          portNum = reader.readVarint();
        case 2:
          payload = reader.readLengthDelimited();
        default:
          reader.skipField(field);
      }
    }
    return _DataPayload(portNum: portNum, payload: payload);
  }

  DecodedMeshEvent _readNodeInfo(List<int> bytes) {
    final reader = ProtobufWireReader(bytes);
    int? nodeNum;
    _UserInfo? user;
    _PositionInfo? position;

    while (!reader.isDone) {
      final field = reader.readField();
      switch (field.number) {
        case 1:
          nodeNum = reader.readVarint();
        case 2:
          user = _readUser(reader.readLengthDelimited());
        case 3:
          position = _readPosition(reader.readLengthDelimited());
        default:
          reader.skipField(field);
      }
    }

    return DecodedMeshEvent(
      type: DecodedMeshEventType.nodeInfo,
      nodeNum: nodeNum,
      longName: user?.longName,
      shortName: user?.shortName,
      latitude: position?.latitude,
      longitude: position?.longitude,
      altitude: position?.altitude,
    );
  }

  _UserInfo _readUser(List<int> bytes) {
    final reader = ProtobufWireReader(bytes);
    String? longName;
    String? shortName;

    while (!reader.isDone) {
      final field = reader.readField();
      switch (field.number) {
        case 2:
          longName = utf8.decode(
            reader.readLengthDelimited(),
            allowMalformed: true,
          );
        case 3:
          shortName = utf8.decode(
            reader.readLengthDelimited(),
            allowMalformed: true,
          );
        default:
          reader.skipField(field);
      }
    }
    return _UserInfo(longName: longName, shortName: shortName);
  }

  _PositionInfo _readPosition(List<int> bytes) {
    final reader = ProtobufWireReader(bytes);
    double? latitude;
    double? longitude;
    int? altitude;

    while (!reader.isDone) {
      final field = reader.readField();
      switch (field.number) {
        case 1:
          latitude = reader.readFixed32(signed: true) / 10000000;
        case 2:
          longitude = reader.readFixed32(signed: true) / 10000000;
        case 3:
          altitude = reader.readVarint();
        default:
          reader.skipField(field);
      }
    }
    return _PositionInfo(
      latitude: latitude,
      longitude: longitude,
      altitude: altitude,
    );
  }
}

class _DataPayload {
  const _DataPayload({required this.portNum, required this.payload});

  final int portNum;
  final List<int> payload;
}

class _UserInfo {
  const _UserInfo({this.longName, this.shortName});

  final String? longName;
  final String? shortName;
}

class _PositionInfo {
  const _PositionInfo({this.latitude, this.longitude, this.altitude});

  final double? latitude;
  final double? longitude;
  final int? altitude;
}
