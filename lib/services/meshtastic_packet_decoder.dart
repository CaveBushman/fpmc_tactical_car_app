import 'dart:convert';

import 'protobuf_wire_reader.dart';

enum DecodedMeshEventType {
  myInfo,
  configComplete,
  nodeInfo,
  position,
  textMessage,
  telemetry,
  routing,
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
    this.heardAt,
    this.configId,
    this.requestId,
    this.routingError,
    this.batteryLevel,
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

  /// Radio-reported receive time (MeshPacket.rx_time / NodeInfo.last_heard),
  /// null when the T-Beam has no valid clock.
  final DateTime? heardAt;

  /// FromRadio.config_complete_id echoed back after a want_config request.
  final int? configId;

  /// ROUTING_APP: id of the packet being acknowledged and its
  /// Routing.error_reason (0 = delivered).
  final int? requestId;
  final int? routingError;

  /// DeviceMetrics.battery_level: 0–100 %, 101 = powered externally.
  final int? batteryLevel;

  String get label {
    final name = longName ?? shortName ?? _nodeLabel(nodeNum ?? from);
    switch (type) {
      case DecodedMeshEventType.myInfo:
        return 'MyNodeInfo ${_nodeLabel(nodeNum)}';
      case DecodedMeshEventType.configComplete:
        return 'Konfigurace načtena';
      case DecodedMeshEventType.nodeInfo:
        final position = _positionLabel;
        return position == null
            ? 'NodeInfo $name'
            : 'NodeInfo $name / $position';
      case DecodedMeshEventType.position:
        return 'Pozice $name / ${_positionLabel ?? 'bez souřadnic'}';
      case DecodedMeshEventType.textMessage:
        return 'Zpráva $name: ${text ?? ''}';
      case DecodedMeshEventType.telemetry:
        return 'Telemetrie $name / baterie ${batteryLevel ?? '-'} %';
      case DecodedMeshEventType.routing:
        return routingError == 0
            ? 'ACK ${_nodeLabel(requestId)} od ${_nodeLabel(from)}'
            : 'NAK ${_nodeLabel(requestId)} chyba $routingError';
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
  static const routingApp = 5;
  static const telemetryApp = 67;
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
        case 3:
          events.add(_readMyInfo(reader.readLengthDelimited()));
        case 4:
          events.add(_readNodeInfo(reader.readLengthDelimited()));
        case 7:
          events.add(
            DecodedMeshEvent(
              type: DecodedMeshEventType.configComplete,
              configId: reader.readVarint(),
            ),
          );
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
    DateTime? heardAt;
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
        case 7:
          heardAt = _epochSeconds(reader.readFixed32());
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
        heardAt: heardAt,
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
        heardAt: heardAt,
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
          heardAt: heardAt,
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
          heardAt: heardAt,
          portNum: payload.portNum,
          latitude: position.latitude,
          longitude: position.longitude,
          altitude: position.altitude,
        );
      case routingApp:
        return DecodedMeshEvent(
          type: DecodedMeshEventType.routing,
          from: from,
          to: to,
          packetId: packetId,
          channelIndex: channelIndex,
          heardAt: heardAt,
          portNum: payload.portNum,
          requestId: payload.requestId,
          routingError: _readRoutingError(payload.payload),
        );
      case telemetryApp:
        return DecodedMeshEvent(
          type: DecodedMeshEventType.telemetry,
          from: from,
          to: to,
          packetId: packetId,
          channelIndex: channelIndex,
          heardAt: heardAt,
          portNum: payload.portNum,
          nodeNum: from,
          batteryLevel: _readTelemetryBattery(payload.payload),
        );
      case nodeInfoApp:
        final user = _readUser(payload.payload);
        return DecodedMeshEvent(
          type: DecodedMeshEventType.nodeInfo,
          from: from,
          to: to,
          packetId: packetId,
          channelIndex: channelIndex,
          heardAt: heardAt,
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
          heardAt: heardAt,
          portNum: payload.portNum,
        );
    }
  }

  int _readRoutingError(List<int> bytes) {
    final reader = ProtobufWireReader(bytes);
    var errorReason = 0;
    while (!reader.isDone) {
      final field = reader.readField();
      switch (field.number) {
        case 3:
          errorReason = reader.readVarint();
        default:
          reader.skipField(field);
      }
    }
    return errorReason;
  }

  DecodedMeshEvent _readMyInfo(List<int> bytes) {
    final reader = ProtobufWireReader(bytes);
    int? myNodeNum;
    while (!reader.isDone) {
      final field = reader.readField();
      switch (field.number) {
        case 1:
          myNodeNum = reader.readVarint();
        default:
          reader.skipField(field);
      }
    }
    return DecodedMeshEvent(
      type: DecodedMeshEventType.myInfo,
      nodeNum: myNodeNum,
    );
  }

  _DataPayload _readData(List<int> bytes) {
    final reader = ProtobufWireReader(bytes);
    var portNum = 0;
    var payload = const <int>[];
    int? requestId;

    while (!reader.isDone) {
      final field = reader.readField();
      switch (field.number) {
        case 1:
          portNum = reader.readVarint();
        case 2:
          payload = reader.readLengthDelimited();
        case 6:
          requestId = reader.readFixed32();
        default:
          reader.skipField(field);
      }
    }
    return _DataPayload(
      portNum: portNum,
      payload: payload,
      requestId: requestId,
    );
  }

  DecodedMeshEvent _readNodeInfo(List<int> bytes) {
    final reader = ProtobufWireReader(bytes);
    int? nodeNum;
    _UserInfo? user;
    _PositionInfo? position;
    DateTime? lastHeard;
    int? batteryLevel;

    while (!reader.isDone) {
      final field = reader.readField();
      switch (field.number) {
        case 1:
          nodeNum = reader.readVarint();
        case 2:
          user = _readUser(reader.readLengthDelimited());
        case 3:
          position = _readPosition(reader.readLengthDelimited());
        case 5:
          lastHeard = _epochSeconds(reader.readFixed32());
        case 6:
          batteryLevel = _readDeviceMetricsBattery(
            reader.readLengthDelimited(),
          );
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
      heardAt: lastHeard,
      batteryLevel: batteryLevel,
    );
  }

  /// Telemetry.device_metrics (field 2) → battery level; null for
  /// environment/power telemetry variants.
  int? _readTelemetryBattery(List<int> bytes) {
    final reader = ProtobufWireReader(bytes);
    int? battery;
    while (!reader.isDone) {
      final field = reader.readField();
      switch (field.number) {
        case 2:
          battery = _readDeviceMetricsBattery(reader.readLengthDelimited());
        default:
          reader.skipField(field);
      }
    }
    return battery;
  }

  int? _readDeviceMetricsBattery(List<int> bytes) {
    final reader = ProtobufWireReader(bytes);
    int? battery;
    while (!reader.isDone) {
      final field = reader.readField();
      switch (field.number) {
        case 1:
          battery = reader.readVarint();
        default:
          reader.skipField(field);
      }
    }
    return battery;
  }

  static DateTime? _epochSeconds(int seconds) {
    // 0 means the radio had no clock; anything before 2020 is equally bogus.
    if (seconds < 1577836800) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
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
  const _DataPayload({
    required this.portNum,
    required this.payload,
    this.requestId,
  });

  final int portNum;
  final List<int> payload;
  final int? requestId;
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
