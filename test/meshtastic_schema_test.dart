import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tactical_car_app/services/meshtastic_packet_decoder.dart';
import 'package:tactical_car_app/services/protobuf_wire_reader.dart';

/// Run via tool/check_meshtastic_schema.sh, which produces a descriptor set
/// from the official (GPL-3.0) .proto files outside the repository.
final _descriptorPath = Platform.environment['MESHTASTIC_DESCRIPTOR_SET'];

// FieldDescriptorProto.Type values.
const _uint32 = 13;
const _fixed32 = 7;
const _sfixed32 = 15;
const _int32 = 5;
const _bool = 8;
const _string = 9;
const _bytes = 12;
const _message = 11;
const _enum = 14;

/// Every field our decoder/encoder reads or writes: number and type.
const _expected = <String, Map<String, (int, int)>>{
  'meshtastic.ToRadio': {
    'packet': (1, _message),
    'want_config_id': (3, _uint32),
  },
  'meshtastic.FromRadio': {
    'packet': (2, _message),
    'my_info': (3, _message),
    'node_info': (4, _message),
    'config_complete_id': (7, _uint32),
    'channel': (10, _message),
  },
  'meshtastic.Channel': {
    'index': (1, _int32),
    'settings': (2, _message),
    'role': (3, _enum),
  },
  'meshtastic.ChannelSettings': {'name': (3, _string)},
  'meshtastic.MeshPacket': {
    'from': (1, _fixed32),
    'to': (2, _fixed32),
    'channel': (3, _uint32),
    'decoded': (4, _message),
    'encrypted': (5, _bytes),
    'id': (6, _fixed32),
    'rx_time': (7, _fixed32),
    'want_ack': (10, _bool),
  },
  'meshtastic.Data': {
    'portnum': (1, _enum),
    'payload': (2, _bytes),
    'request_id': (6, _fixed32),
  },
  'meshtastic.MyNodeInfo': {'my_node_num': (1, _uint32)},
  'meshtastic.NodeInfo': {
    'num': (1, _uint32),
    'user': (2, _message),
    'position': (3, _message),
    'last_heard': (5, _fixed32),
    'device_metrics': (6, _message),
  },
  'meshtastic.User': {'long_name': (2, _string), 'short_name': (3, _string)},
  'meshtastic.Position': {
    'latitude_i': (1, _sfixed32),
    'longitude_i': (2, _sfixed32),
    'altitude': (3, _int32),
    'time': (4, _fixed32),
  },
  'meshtastic.Routing': {'error_reason': (3, _enum)},
  'meshtastic.Waypoint': {
    'id': (1, _uint32),
    'latitude_i': (2, _sfixed32),
    'longitude_i': (3, _sfixed32),
    'expire': (4, _uint32),
    'name': (6, _string),
    'description': (7, _string),
  },
  'meshtastic.Telemetry': {'device_metrics': (2, _message)},
  'meshtastic.DeviceMetrics': {'battery_level': (1, _uint32)},
};

const _expectedPorts = <String, int>{
  'TEXT_MESSAGE_APP': MeshtasticPacketDecoder.textMessageApp,
  'POSITION_APP': MeshtasticPacketDecoder.positionApp,
  'NODEINFO_APP': MeshtasticPacketDecoder.nodeInfoApp,
  'ROUTING_APP': MeshtasticPacketDecoder.routingApp,
  'WAYPOINT_APP': MeshtasticPacketDecoder.waypointApp,
  'TELEMETRY_APP': MeshtasticPacketDecoder.telemetryApp,
};

class _Schema {
  final Map<String, Map<String, (int, int)>> messages = {};
  final Map<String, Map<String, int>> enums = {};
}

/// Reads a FileDescriptorSet with our own wire reader (no generated code).
_Schema _parse(List<int> bytes) {
  final schema = _Schema();
  final set = ProtobufWireReader(bytes);
  while (!set.isDone) {
    final field = set.readField();
    if (field.number != 1) {
      set.skipField(field);
      continue;
    }
    final file = ProtobufWireReader(set.readLengthDelimited());
    var package = '';
    final messages = <List<int>>[];
    final enums = <List<int>>[];
    while (!file.isDone) {
      final f = file.readField();
      switch (f.number) {
        case 2:
          package = utf8.decode(file.readLengthDelimited());
        case 4:
          messages.add(file.readLengthDelimited());
        case 5:
          enums.add(file.readLengthDelimited());
        default:
          file.skipField(f);
      }
    }
    for (final message in messages) {
      _readMessage(schema, package, message);
    }
    for (final enumBytes in enums) {
      _readEnum(schema, package, enumBytes);
    }
  }
  return schema;
}

void _readMessage(_Schema schema, String scope, List<int> bytes) {
  final reader = ProtobufWireReader(bytes);
  var name = '';
  final fields = <String, (int, int)>{};
  final nested = <List<int>>[];
  final nestedEnums = <List<int>>[];
  while (!reader.isDone) {
    final f = reader.readField();
    switch (f.number) {
      case 1:
        name = utf8.decode(reader.readLengthDelimited());
      case 2:
        final field = ProtobufWireReader(reader.readLengthDelimited());
        var fieldName = '';
        var number = 0;
        var type = 0;
        while (!field.isDone) {
          final ff = field.readField();
          switch (ff.number) {
            case 1:
              fieldName = utf8.decode(field.readLengthDelimited());
            case 3:
              number = field.readVarint();
            case 5:
              type = field.readVarint();
            default:
              field.skipField(ff);
          }
        }
        fields[fieldName] = (number, type);
      case 3:
        nested.add(reader.readLengthDelimited());
      case 4:
        nestedEnums.add(reader.readLengthDelimited());
      default:
        reader.skipField(f);
    }
  }
  final fullName = '$scope.$name';
  schema.messages[fullName] = fields;
  for (final child in nested) {
    _readMessage(schema, fullName, child);
  }
  for (final child in nestedEnums) {
    _readEnum(schema, fullName, child);
  }
}

void _readEnum(_Schema schema, String scope, List<int> bytes) {
  final reader = ProtobufWireReader(bytes);
  var name = '';
  final values = <String, int>{};
  while (!reader.isDone) {
    final f = reader.readField();
    switch (f.number) {
      case 1:
        name = utf8.decode(reader.readLengthDelimited());
      case 2:
        final value = ProtobufWireReader(reader.readLengthDelimited());
        var valueName = '';
        var number = 0;
        while (!value.isDone) {
          final vf = value.readField();
          switch (vf.number) {
            case 1:
              valueName = utf8.decode(value.readLengthDelimited());
            case 2:
              number = value.readVarint();
            default:
              value.skipField(vf);
          }
        }
        values[valueName] = number;
      default:
        reader.skipField(f);
    }
  }
  schema.enums['$scope.$name'] = values;
}

void main() {
  final skip = _descriptorPath == null
      ? 'MESHTASTIC_DESCRIPTOR_SET not set; run tool/check_meshtastic_schema.sh'
      : null;

  test('decoder and encoder fields match the Meshtastic schema', () {
    final schema = _parse(File(_descriptorPath!).readAsBytesSync());
    final problems = <String>[];
    _expected.forEach((message, fields) {
      final actual = schema.messages[message];
      if (actual == null) {
        problems.add('$message missing from schema');
        return;
      }
      fields.forEach((field, expected) {
        final found = actual[field];
        if (found != expected) {
          problems.add('$message.$field: expected $expected, schema $found');
        }
      });
    });
    expect(problems, isEmpty, reason: problems.join('\n'));
  }, skip: skip);

  test('port numbers match PortNum', () {
    final schema = _parse(File(_descriptorPath!).readAsBytesSync());
    final ports = schema.enums['meshtastic.PortNum'];
    expect(ports, isNotNull);
    _expectedPorts.forEach((name, number) {
      expect(ports![name], number, reason: name);
    });
  }, skip: skip);
}
