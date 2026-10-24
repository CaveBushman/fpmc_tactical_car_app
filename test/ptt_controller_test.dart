import 'package:flutter_test/flutter_test.dart';
import 'package:tactical_car_app/controllers/ptt_controller.dart';
import 'package:tactical_car_app/services/backend_client.dart';
import 'package:tactical_car_app/services/ptt/voice_transport.dart';

import 'support/fakes.dart';

void main() {
  late DateTime now;
  late List<FakeVoiceTransport> transports;
  late PttController ptt;

  PttController build({PttJoiner? joiner}) => PttController(
    joiner: joiner ?? (_) async => fakeJoinInfo(),
    transportFactory: () {
      final transport = FakeVoiceTransport();
      transports.add(transport);
      return transport;
    },
    clock: () => now,
    floorTimeout: const Duration(seconds: 60),
  );

  setUp(() {
    now = DateTime.utc(2026, 10, 24, 12);
    transports = [];
    ptt = build();
  });

  tearDown(() => ptt.dispose());

  Future<void> settle() => pumpEventQueue();

  test('joins the group room with backend keys', () async {
    await ptt.joinGroup('alpha', 'ALPHA');

    expect(ptt.status, PttStatus.ready);
    expect(ptt.channel, 'ALPHA');
    expect(ptt.keyId, 3);
    expect(transports.last.connectedWith!.keys.map((k) => k.id), [2, 3]);
    expect(transports.last.microphoneEnabled, isFalse);
  });

  test('press takes the floor and opens the mic, release closes it', () async {
    await ptt.joinGroup('alpha', 'ALPHA');

    expect(await ptt.press(), isTrue);
    expect(ptt.status, PttStatus.transmitting);
    expect(transports.last.microphoneEnabled, isTrue);
    expect(transports.last.sent.single['op'], 'take');

    await ptt.release();
    expect(ptt.status, PttStatus.ready);
    expect(transports.last.microphoneEnabled, isFalse);
    expect(transports.last.sent.last['op'], 'release');
  });

  test('another speaker blocks PTT until they release', () async {
    await ptt.joinGroup('alpha', 'ALPHA');

    transports.last.remoteFloor('medic', 'take', now);
    await settle();
    expect(ptt.status, PttStatus.receiving);
    expect(ptt.speaker, 'medic');
    expect(await ptt.press(), isFalse);
    expect(transports.last.microphoneEnabled, isFalse);

    transports.last.remoteFloor(
      'medic',
      'release',
      now.add(const Duration(seconds: 3)),
    );
    await settle();
    expect(ptt.status, PttStatus.ready);
    expect(ptt.speaker, isNull);
  });

  test('simultaneous take: earlier press wins, the other yields', () async {
    await ptt.joinGroup('alpha', 'ALPHA');
    await ptt.press();

    // Their take is later: we keep the floor.
    transports.last.remoteFloor(
      'medic',
      'take',
      now.add(const Duration(milliseconds: 50)),
    );
    await settle();
    expect(ptt.status, PttStatus.transmitting);
    expect(transports.last.microphoneEnabled, isTrue);

    // An earlier take wins over ours: we close the mic and listen.
    transports.last.remoteFloor(
      'commander',
      'take',
      now.subtract(const Duration(milliseconds: 20)),
    );
    await settle();
    expect(ptt.status, PttStatus.receiving);
    expect(ptt.speaker, 'commander');
    expect(transports.last.microphoneEnabled, isFalse);
  });

  test('ignores replayed or stale floor messages', () async {
    await ptt.joinGroup('alpha', 'ALPHA');

    transports.last.remoteFloor(
      'medic',
      'take',
      now.subtract(const Duration(minutes: 5)),
    );
    await settle();
    expect(ptt.status, PttStatus.ready);

    transports.last.remoteFloor('medic', 'take', now);
    // Release older than the take (from a previous transmission).
    transports.last.remoteFloor(
      'medic',
      'release',
      now.subtract(const Duration(seconds: 5)),
    );
    // Release by someone who does not hold the floor.
    transports.last.remoteFloor(
      'commander',
      'release',
      now.add(const Duration(seconds: 1)),
    );
    await settle();
    expect(ptt.status, PttStatus.receiving);
  });

  test('floor is freed when the holder leaves or times out', () async {
    await ptt.joinGroup('alpha', 'ALPHA');
    transports.last.remoteFloor('medic', 'take', now);
    await settle();

    transports.last.emit(const VoiceParticipantLeft('medic'));
    await settle();
    expect(ptt.status, PttStatus.ready);

    ptt.dispose();
    ptt = PttController(
      joiner: (_) async => fakeJoinInfo(),
      transportFactory: () {
        final t = FakeVoiceTransport();
        transports.add(t);
        return t;
      },
      clock: () => now,
      floorTimeout: const Duration(milliseconds: 20),
    );
    await ptt.joinGroup('alpha', 'ALPHA');
    transports.last.remoteFloor('medic', 'take', now);
    await settle();
    expect(ptt.status, PttStatus.receiving);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(ptt.status, PttStatus.ready);
  });

  test('switching group leaves the previous room', () async {
    await ptt.joinGroup('alpha', 'ALPHA');
    final first = transports.last;

    await ptt.joinGroup('bravo', 'BRAVO');

    expect(first.disposed, isTrue);
    expect(transports, hasLength(2));
    expect(ptt.channel, 'BRAVO');
  });

  test('backend refusal and lost connection end in error', () async {
    ptt.dispose();
    ptt = build(
      joiner: (_) async => throw const BackendException(403, 'forbidden_group'),
    );
    await ptt.joinGroup('command', 'COMMAND');
    expect(ptt.status, PttStatus.error);
    expect(ptt.error, contains('přístup'));

    ptt.dispose();
    ptt = build();
    await ptt.joinGroup('alpha', 'ALPHA');
    transports.last.emit(const VoiceDisconnected('server_shutdown'));
    await settle();
    expect(ptt.status, PttStatus.error);
    expect(await ptt.press(), isFalse);
  });

  test('demo mode works without a voice server', () async {
    ptt.dispose();
    ptt = PttController();
    await ptt.joinGroup('alpha', 'ALPHA');

    expect(ptt.isDemo, isTrue);
    expect(ptt.status, PttStatus.ready);
    expect(await ptt.press(), isTrue);
    expect(ptt.status, PttStatus.transmitting);
    await ptt.release();
    expect(ptt.status, PttStatus.ready);
  });
}
