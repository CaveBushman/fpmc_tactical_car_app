import 'dart:async';

/// Reads the Meshtastic FromRadio characteristic until it returns an empty
/// value. The radio queues packets and a single FromNum notification may
/// stand for several of them, so reading only once loses data.
///
/// Concurrent [drain] calls are coalesced: a trigger that arrives while a
/// drain is running schedules one more pass instead of a parallel read.
class FromRadioDrainer {
  FromRadioDrainer({
    required this.read,
    required this.onPacket,
    this.maxPacketsPerPass = 512,
  });

  final Future<List<int>> Function() read;
  final void Function(List<int> bytes) onPacket;
  final int maxPacketsPerPass;
  Future<void>? _running;
  bool _pending = false;

  Future<void> drain() {
    final running = _running;
    if (running != null) {
      _pending = true;
      return running;
    }
    final future = _run();
    _running = future;
    return future;
  }

  Future<void> _run() async {
    try {
      do {
        _pending = false;
        for (var i = 0; i < maxPacketsPerPass; i++) {
          final bytes = await read();
          if (bytes.isEmpty) {
            break;
          }
          onPacket(bytes);
        }
      } while (_pending);
    } finally {
      _running = null;
    }
  }
}
