import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:tactical_car_app/controllers/tactical_controller.dart';
import 'package:tactical_car_app/models/navigation.dart';
import 'package:tactical_car_app/models/rendezvous.dart';
import 'package:tactical_car_app/services/mesh_packet_repository.dart';
import 'package:tactical_car_app/services/meshtastic_ble_service.dart';
import 'package:tactical_car_app/widgets/rendezvous_banner.dart';

import 'support/fakes.dart';
import 'support/mesh_bytes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('model', () {
    final now = DateTime(2026, 10, 24, 14, 0);

    test('round-trips and reads the next occurrence', () {
      final meeting = Rendezvous(
        code: 'RV-1',
        at: DateTime(2026, 10, 24, 14, 30),
        setBy: 'ALFA',
      );
      expect(meeting.shareText, 'SRAZ | RV-1 | 14:30 | ALFA');
      final parsed = Rendezvous.parse(meeting.shareText, now: now)!;
      expect(parsed.code, 'RV-1');
      expect(parsed.at, DateTime(2026, 10, 24, 14, 30));
      expect(parsed.setBy, 'ALFA');

      // Shortly past counts as today; earlier means tomorrow.
      expect(
        Rendezvous.parse('SRAZ | RV-1 | 13:20 | ALFA', now: now)!.at,
        DateTime(2026, 10, 24, 13, 20),
      );
      expect(
        Rendezvous.parse('SRAZ | RV-1 | 06:00 | ALFA', now: now)!.at,
        DateTime(2026, 10, 25, 6, 0),
      );
      expect(Rendezvous.parse('SRAZ | RV-1 | 25:00 | ALFA', now: now), isNull);
      expect(Rendezvous.parseCancel('SRAZ ZRUŠEN | RV-1'), 'RV-1');
      expect(Rendezvous.parseCancel('OK'), isNull);
    });

    test('is over half an hour after the time', () {
      final meeting = Rendezvous(code: 'RV', at: now, setBy: 'A');
      expect(meeting.isOverAt(now.add(const Duration(minutes: 29))), isFalse);
      expect(meeting.isOverAt(now.add(const Duration(minutes: 31))), isTrue);
    });
  });

  test('controller sets, receives, cancels and expires meetings', () async {
    var offset = Duration.zero;
    final repository = MeshPacketRepository();
    final controller = TacticalController(
      locationService: FakeLocationService(),
      meshtasticBleService: FakeBleService(),
      meshPacketRepository: repository,
      nativePtt: FakeNativePttBridge(),
      carBridge: FakeCarBridge(),
      clock: () => DateTime.now().add(offset),
    );
    addTearDown(controller.dispose);
    await controller.login('operator', 'operator-2026');
    var packetId = 120;
    Future<void> receive(String text) async {
      repository.ingest(
        MeshtasticBlePacket(
          bytes: fromRadioText(
            from: 0xA1100002,
            text: text,
            packetId: packetId++,
          ),
          receivedAt: DateTime.now(),
        ),
      );
      await pumpEventQueue();
    }

    final obs = controller.waypoints.firstWhere((w) => w.code == 'OBS-2');
    final at = DateTime.now().add(const Duration(minutes: 40));
    await controller.setRendezvous(obs, at);
    expect(controller.rendezvous!.code, 'OBS-2');
    expect(controller.messages.first.body, startsWith('SRAZ | OBS-2 | '));
    expect(controller.rendezvousSolution!.label, 'OBS-2');

    await controller.cancelRendezvous();
    expect(controller.rendezvous, isNull);
    expect(controller.messages.first.body, 'SRAZ ZRUŠEN | OBS-2');

    String two(int v) => v.toString().padLeft(2, '0');
    final clock = '${two(at.hour)}:${two(at.minute)}';
    await receive('SRAZ | OBS-2 | $clock | RAVEN-2');
    expect(controller.rendezvous!.setBy, 'RAVEN-2');
    await receive('SRAZ ZRUŠEN | OTHER');
    expect(controller.rendezvous, isNotNull); // a different meeting
    await receive('SRAZ ZRUŠEN | OBS-2');
    expect(controller.rendezvous, isNull);

    await receive('SRAZ | OBS-2 | $clock | RAVEN-2');
    offset = const Duration(minutes: 75); // 35 min after the meeting
    expect(controller.rendezvous, isNull);
    expect(
      controller.missionEvents.map((e) => e.text),
      contains(startsWith('Sraz OBS-2 v')),
    );
  });

  testWidgets('banner turns red when the trip is longer than the time left', (
    tester,
  ) async {
    TacticalNavSolution solution(double km) => TacticalNavSolution(
      label: 'RV',
      kind: TacticalNavTargetKind.rally,
      icon: Icons.flag,
      mgrs: '',
      distanceKm: km,
      bearingDeg: 0,
      position: const LatLng(50, 14),
    );
    final meeting = Rendezvous(
      code: 'RV',
      at: DateTime.now().add(const Duration(minutes: 20, seconds: 30)),
      setBy: 'ALFA',
    );
    Future<String> subtitle(double km) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RendezvousBanner(
              meeting: meeting,
              isOwn: false,
              solution: solution(km),
              onClose: () {},
            ),
          ),
        ),
      );
      return tester
          .widget<Text>(find.byKey(const ValueKey('rendezvous-subtitle')))
          .data!;
    }

    expect(await subtitle(1), 'za 20 min · cesta 12 min · od ALFA');
    expect(await subtitle(3), 'za 20 min · nestihnete: cesta 36 min · od ALFA');
  });
}
