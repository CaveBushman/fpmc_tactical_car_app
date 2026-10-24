/// One FromRadio frame with its offset from the start of a recording.
class RecordedPacket {
  const RecordedPacket({required this.offset, required this.bytes});

  final Duration offset;
  final List<int> bytes;
}

/// Plain-text session recording: one frame per line,
/// `<milliseconds since start> <hex bytes>`; `#` starts a comment.
class PacketRecording {
  const PacketRecording(this.packets);

  final List<RecordedPacket> packets;

  static PacketRecording parse(String text) {
    final packets = <RecordedPacket>[];
    for (final rawLine in text.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) {
        continue;
      }
      final space = line.indexOf(' ');
      if (space == -1) {
        throw FormatException('Missing offset or data', line);
      }
      final offsetMs = int.parse(line.substring(0, space));
      final hex = line.substring(space + 1).replaceAll(RegExp(r'\s+'), '');
      if (hex.length.isOdd) {
        throw FormatException('Odd hex length', line);
      }
      packets.add(
        RecordedPacket(
          offset: Duration(milliseconds: offsetMs),
          bytes: [
            for (var i = 0; i < hex.length; i += 2)
              int.parse(hex.substring(i, i + 2), radix: 16),
          ],
        ),
      );
    }
    return PacketRecording(packets);
  }

  String serialize({String? comment}) {
    final buffer = StringBuffer();
    if (comment != null) {
      for (final line in comment.split('\n')) {
        buffer.writeln('# $line');
      }
    }
    for (final packet in packets) {
      buffer
        ..write(packet.offset.inMilliseconds)
        ..write(' ')
        ..writeln(
          packet.bytes
              .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
              .join(),
        );
    }
    return buffer.toString();
  }
}
