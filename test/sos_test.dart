import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tactical_car_app/app.dart';
import 'package:tactical_car_app/controllers/tactical_controller.dart';
import 'package:tactical_car_app/models/sos.dart';
import 'package:tactical_car_app/services/mesh_packet_repository.dart';
import 'package:tactical_car_app/services/meshtastic_ble_service.dart';

import 'support/fakes.dart';
import 'support/mesh_bytes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('signal format', () {
    test('call round-trips with position', () {
      final text = SosSignal.call(
        callSign: 'RAVEN-2',
        mgrs: '33U VR 58556 48514',
        latitude: 50.087451,
        longitude: 14.420671,
      );
      final call = SosSignal.parse(text) as SosCall;
      expect(call.callSign, 'RAVEN-2');
      expect(call.mgrs, '33U VR 58556 48514');
      expect(call.latitude, 50.087451);
      expect(call.longitude, 14.420671);
    });

    test('cancel, ack, legacy and non-SOS text', () {
      expect(
        (SosSignal.parse(SosSignal.cancel('X')) as SosCancel).callSign,
        'X',
      );
      final ack = SosSignal.parse(SosSignal.ack(from: 'A', to: 'B')) as SosAck;
      expect((ack.from, ack.to), ('A', 'B'));
      final legacy = SosSignal.parse('SOS') as SosCall;
      expect(legacy.callSign, isNull);
      expect(legacy.latitude, isNull);
      expect(SosSignal.parse('SOSNA je strom'), isNull);
      expect(SosSignal.parse('NA POZICI | MGRS x'), isNull);
      final bad = SosSignal.parse('SOS | X | LAT 99 | LON 14') as SosCall;
      expect(bad.latitude, isNull);
    });
  });

  group('controller', () {
    late FakeBleService ble;
    late MeshPacketRepository repository;
    late TacticalController controller;

    setUp(() async {
      ble = FakeBleService();
      repository = MeshPacketRepository();
      controller = TacticalController(
        locationService: FakeLocationService(),
        meshtasticBleService: ble,
        meshPacketRepository: repository,
        nativePtt: FakeNativePttBridge(),
        carBridge: FakeCarBridge(),
        sosRepeat: const Duration(milliseconds: 30),
      );
      await controller.login('operator', 'operator-2026');
    });

    tearDown(() => controller.dispose());

    void receive(String text, {int id = 1, int from = 0xA1100002}) =>
        repository.ingest(
          MeshtasticBlePacket(
            bytes: fromRadioText(from: from, text: text, packetId: id),
            receivedAt: DateTime.now(),
          ),
        );

    test('own SOS repeats with position until cancelled', () async {
      await controller.startSos();
      expect(controller.sosActive, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 80));

      final calls = controller.messages.where(
        (m) => m.body.startsWith('SOS | '),
      );
      expect(calls.length, greaterThanOrEqualTo(2));
      expect(calls.first.priority, isTrue);
      expect(calls.first.body, contains(controller.selfNode.mgrs));
      expect(
        controller.activeSosAlerts,
        isEmpty,
        reason: 'own call is no alert',
      );

      await controller.stopSos();
      final count = controller.messages
          .where((m) => m.body.startsWith('SOS | '))
          .length;
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(controller.sosActive, isFalse);
      expect(controller.messages.first.body, startsWith('SOS ZRUŠENO'));
      expect(
        controller.messages.where((m) => m.body.startsWith('SOS | ')).length,
        count,
      );
    });

    test('incoming call raises an alert and a map point', () async {
      receive(
        SosSignal.call(
          callSign: 'RAVEN-2',
          mgrs: '33U VR 1 2',
          latitude: 50.09,
          longitude: 14.41,
        ),
      );
      await pumpEventQueue();

      final alert = controller.activeSosAlerts.single;
      expect(alert.callSign, 'RAVEN-2');
      final point = controller.waypoints.firstWhere(
        (w) => w.code == 'SOS-RAVEN-2',
      );
      expect(point.priority, isTrue);
      expect(point.latitude, 50.09);

      await controller.acknowledgeSos(alert);
      expect(controller.activeSosAlerts, isEmpty);
      expect(
        controller.messages.first.body,
        'SOS PŘIJATO | RAVEN-1 -> RAVEN-2',
      );

      // A repeat stays acknowledged; the point follows the new position.
      receive(
        SosSignal.call(
          callSign: 'RAVEN-2',
          mgrs: 'x',
          latitude: 50.1,
          longitude: 14.41,
        ),
        id: 2,
      );
      await pumpEventQueue();
      expect(controller.activeSosAlerts, isEmpty);
      expect(
        controller.waypoints
            .firstWhere((w) => w.code == 'SOS-RAVEN-2')
            .latitude,
        50.1,
      );

      receive(SosSignal.cancel('RAVEN-2'), id: 3);
      await pumpEventQueue();
      expect(controller.waypoints.any((w) => w.code == 'SOS-RAVEN-2'), isFalse);
    });

    test('legacy plain SOS alerts with the sender name', () async {
      receive('SOS');
      await pumpEventQueue();
      expect(controller.activeSosAlerts.single.callSign, 'RAVEN-2');
    });
  });

  testWidgets('SOS button confirms, shows the banner and cancels', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 932);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      TacticalCarApp(
        locationService: FakeLocationService(),
        meshtasticBleService: FakeBleService(),
      ),
    );
    await tester.enterText(find.byType(TextField).first, 'operator');
    await tester.enterText(find.byType(TextField).at(1), 'operator-2026');
    await tester.tap(find.text('Přihlásit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Zprávy'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('SOS'));
    await tester.pumpAndSettle();
    expect(find.text('Spustit SOS?'), findsOneWidget);
    await tester.tap(find.text('SPUSTIT SOS'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('sos-own')), findsOneWidget);
    expect(find.textContaining('SOS | RAVEN-1 | MGRS'), findsOneWidget);

    await tester.tap(find.text('Zrušit'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('sos-own')), findsNothing);
    expect(find.textContaining('SOS ZRUŠENO | RAVEN-1'), findsOneWidget);
  });
}
