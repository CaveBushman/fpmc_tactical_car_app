import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tactical_car_app/services/from_radio_drainer.dart';

void main() {
  test('reads until the radio returns an empty packet', () async {
    final queue = <List<int>>[
      [1],
      [2],
      [3],
      [],
    ];
    final received = <List<int>>[];
    final drainer = FromRadioDrainer(
      read: () async => queue.removeAt(0),
      onPacket: received.add,
    );

    await drainer.drain();

    expect(received, [
      [1],
      [2],
      [3],
    ]);
  });

  test('coalesces triggers that arrive during a drain', () async {
    final gate = Completer<void>();
    var reads = 0;
    final queue = <List<int>>[
      [1],
      [],
      [2],
      [],
    ];
    final received = <List<int>>[];
    final drainer = FromRadioDrainer(
      read: () async {
        reads++;
        if (reads == 1) {
          await gate.future;
        }
        return queue.removeAt(0);
      },
      onPacket: received.add,
    );

    final first = drainer.drain();
    final second = drainer.drain();
    final third = drainer.drain();
    gate.complete();
    await Future.wait([first, second, third]);

    // One extra pass for the queued triggers, never parallel reads.
    expect(reads, 4);
    expect(received, [
      [1],
      [2],
    ]);
  });
}
