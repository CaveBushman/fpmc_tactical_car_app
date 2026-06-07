class ProtobufWireWriter {
  final List<int> _bytes = [];

  List<int> get bytes => List.unmodifiable(_bytes);

  void writeVarint(int fieldNumber, int value) {
    _writeKey(fieldNumber, 0);
    _writeRawVarint(value);
  }

  void writeBool(int fieldNumber, bool value) {
    writeVarint(fieldNumber, value ? 1 : 0);
  }

  void writeFixed32(int fieldNumber, int value) {
    _writeKey(fieldNumber, 5);
    final unsigned = value & 0xFFFFFFFF;
    _bytes
      ..add(unsigned & 0xFF)
      ..add((unsigned >> 8) & 0xFF)
      ..add((unsigned >> 16) & 0xFF)
      ..add((unsigned >> 24) & 0xFF);
  }

  void writeBytes(int fieldNumber, List<int> value) {
    _writeKey(fieldNumber, 2);
    _writeRawVarint(value.length);
    _bytes.addAll(value);
  }

  void writeMessage(int fieldNumber, ProtobufWireWriter message) {
    writeBytes(fieldNumber, message._bytes);
  }

  void _writeKey(int fieldNumber, int wireType) {
    _writeRawVarint((fieldNumber << 3) | wireType);
  }

  void _writeRawVarint(int value) {
    var remaining = value;
    while (remaining >= 0x80) {
      _bytes.add((remaining & 0x7F) | 0x80);
      remaining >>= 7;
    }
    _bytes.add(remaining);
  }
}
