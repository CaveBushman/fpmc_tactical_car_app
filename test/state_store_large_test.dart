import 'package:flutter_test/flutter_test.dart';
import 'package:tactical_car_app/services/tactical_state_store.dart';

void main() {
  test('a full mission state is saved and read back', () async {
    final now = DateTime.now().toUtc().toIso8601String();
    final track = [
      for (var i = 0; i < 5000; i++)
        {'lat': 50 + i * 1e-5, 'lon': 14 + i * 1e-5, 'alt': 200, 'at': now},
    ];
    final messages = [
      for (var i = 0; i < 150; i++)
        {
          'sender': 'RAVEN-$i',
          'body':
              'NA POZICI | MGRS 33U VR 58335 40478 | LAT 50.012345 | LON 14.456789',
          'sentAt': now,
          'groupId': 'alpha',
        },
    ];
    final events = [
      for (var i = 0; i < 500; i++)
        {'at': now, 'kind': 'status', 'text': 'SCOUT-3: ZRANĚN $i'},
    ];
    final nodes = [
      for (var i = 0; i < 20; i++)
        {'nodeNum': i, 'callSign': 'N$i', 'latitude': 50.0, 'longitude': 14.0},
    ];
    const store = TacticalStateStore();
    await store.save(nodes: nodes, messages: messages, owner: 'x'); // key
    final watch = Stopwatch()..start();
    const runs = 5;
    for (var i = 0; i < runs; i++) {
      await store.save(
        nodes: nodes,
        messages: messages,
        track: track,
        events: events,
        owner: 'x',
      );
    }
    watch.stop();
    // Sealed in a background isolate (well above the threshold) and still
    // readable.
    final restored = await store.load();
    expect(restored!.track, hasLength(5000));
    expect(restored.events, hasLength(500));
  });
}
