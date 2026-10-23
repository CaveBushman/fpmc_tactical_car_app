import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tactical_car_app/app.dart';
import 'package:tactical_car_app/models/messaging.dart';
import 'package:tactical_car_app/services/mesh_packet_repository.dart';
import 'package:tactical_car_app/services/meshtastic_ble_service.dart';
import 'package:tactical_car_app/services/protobuf_wire_reader.dart';

import 'support/fakes.dart';
import 'support/mesh_bytes.dart';

/// Extracts MeshPacket.id from a ToRadio{packet} frame.
int writtenPacketId(List<int> toRadio) {
  final outer = ProtobufWireReader(toRadio);
  outer.readField();
  final packet = ProtobufWireReader(outer.readLengthDelimited());
  while (!packet.isDone) {
    final field = packet.readField();
    if (field.number == 6) {
      return packet.readFixed32();
    }
    packet.skipField(field);
  }
  throw StateError('no packet id');
}

List<int> fromRadioRouting({
  required int from,
  required int requestId,
  int errorReason = 0,
}) {
  return pbMessage(2, [
    ...pbFixed32(1, from),
    ...pbFixed32(2, 0xA1100001),
    ...pbMessage(4, [
      ...pbVarint(1, 5),
      ...pbMessage(2, pbVarint(3, errorReason)),
      ...pbFixed32(6, requestId),
    ]),
  ]);
}

void main() {
  Future<(FakeBleService, MeshPacketRepository)> openMessages(
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 932);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final ble = FakeBleService();
    final repository = MeshPacketRepository();
    await tester.pumpWidget(
      TacticalCarApp(
        meshtasticBleService: ble,
        meshPacketRepository: repository,
      ),
    );
    await tester.enterText(find.byType(TextField).first, 'operator');
    await tester.enterText(find.byType(TextField).at(1), 'operator-2026');
    await tester.tap(find.text('Přihlásit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Zprávy'));
    await tester.pumpAndSettle();
    return (ble, repository);
  }

  testWidgets('message turns delivered on routing ACK', (tester) async {
    final (ble, repository) = await openMessages(tester);

    await tester.tap(find.text('NA POZICI'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Předáno do T-Beamu'), findsOneWidget);

    final packetId = writtenPacketId(ble.written.single);
    repository.ingest(
      MeshtasticBlePacket(
        bytes: fromRadioRouting(from: 0xA1100001, requestId: packetId),
        receivedAt: DateTime.now(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('Doručeno'), findsOneWidget);
  });

  testWidgets('routing error marks message failed and retryable', (
    tester,
  ) async {
    final (ble, repository) = await openMessages(tester);

    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    final packetId = writtenPacketId(ble.written.single);
    repository.ingest(
      MeshtasticBlePacket(
        bytes: fromRadioRouting(
          from: 0xA1100002,
          requestId: packetId,
          errorReason: 5,
        ),
        receivedAt: DateTime.now(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('Doručení selhalo'), findsOneWidget);
    expect(find.text('Odeslat znovu'), findsOneWidget);
  });

  testWidgets('message not handed to radio can be retried', (tester) async {
    final (ble, _) = await openMessages(tester);
    ble.connected = false;

    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Neodesláno, T-Beam nepřipojen'), findsOneWidget);
    expect(ble.written, isEmpty);

    ble.connected = true;
    await tester.tap(find.text('Odeslat znovu'));
    await tester.pumpAndSettle();

    expect(ble.written, hasLength(1));
    expect(find.byTooltip('Předáno do T-Beamu'), findsOneWidget);
    expect(find.text('Odeslat znovu'), findsNothing);
  });

  test('legacy pending snapshot restores as not sent', () {
    final message = MeshMessage.fromJson({
      'sender': 'RAVEN-1',
      'body': 'OK',
      'time': '12:00',
      'groupId': 'alpha',
      'pending': true,
    });
    expect(message.delivery, MessageDelivery.notSent);
    expect(message.canRetry, isTrue);
  });

  test('in-flight message restores as not sent', () {
    const message = MeshMessage(
      sender: 'RAVEN-1',
      body: 'OK',
      time: '12:00',
      groupId: 'alpha',
      delivery: MessageDelivery.sending,
      packetId: 7,
    );
    expect(
      MeshMessage.fromJson(message.toJson()).delivery,
      MessageDelivery.notSent,
    );
  });
}
