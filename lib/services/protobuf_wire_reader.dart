class ProtobufWireReader {
  ProtobufWireReader(List<int> bytes) : _bytes = bytes;

  final List<int> _bytes;
  int _offset = 0;

  bool get isDone => _offset >= _bytes.length;

  ProtobufField readField() {
    final key = readVarint();
    return ProtobufField(number: key >> 3, wireType: key & 0x07);
  }

  int readVarint() {
    var result = 0;
    var shift = 0;
    while (_offset < _bytes.length) {
      final byte = _bytes[_offset++];
      result |= (byte & 0x7f) << shift;
      if ((byte & 0x80) == 0) {
        return result;
      }
      shift += 7;
      if (shift > 63) {
        throw const FormatException('Invalid protobuf varint.');
      }
    }
    throw const FormatException('Unexpected end of protobuf varint.');
  }

  int readFixed32({bool signed = false}) {
    _requireAvailable(4);
    final value =
        _bytes[_offset] |
        (_bytes[_offset + 1] << 8) |
        (_bytes[_offset + 2] << 16) |
        (_bytes[_offset + 3] << 24);
    _offset += 4;
    if (signed && (value & 0x80000000) != 0) {
      return value - 0x100000000;
    }
    return value;
  }

  int readFixed64() {
    _requireAvailable(8);
    final low = readFixed32();
    final high = readFixed32();
    return low | (high << 32);
  }

  List<int> readLengthDelimited() {
    final length = readVarint();
    _requireAvailable(length);
    final value = _bytes.sublist(_offset, _offset + length);
    _offset += length;
    return value;
  }

  void skipField(ProtobufField field) {
    switch (field.wireType) {
      case 0:
        readVarint();
      case 1:
        _requireAvailable(8);
        _offset += 8;
      case 2:
        readLengthDelimited();
      case 5:
        _requireAvailable(4);
        _offset += 4;
      default:
        throw FormatException(
          'Unsupported protobuf wire type ${field.wireType}.',
        );
    }
  }

  void _requireAvailable(int count) {
    if (_offset + count > _bytes.length) {
      throw const FormatException('Unexpected end of protobuf field.');
    }
  }
}

class ProtobufField {
  const ProtobufField({required this.number, required this.wireType});

  final int number;
  final int wireType;
}
