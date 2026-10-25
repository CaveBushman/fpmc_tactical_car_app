import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tactical_car_app/controllers/tactical_controller.dart';
import 'package:tactical_car_app/models/messaging.dart';
import 'package:tactical_car_app/screens/messages_page.dart';

MeshMessage _order({DateTime? acknowledgedAt, bool priority = true}) =>
    MeshMessage(
      sender: TacticalController.hqSender,
      body: 'Stáhnout se na RV-1, trasa přes most',
      sentAt: DateTime.now(),
      groupId: 'alpha',
      targetLabel: 'ALPHA',
      priority: priority,
      viaInternet: true,
      hqMessageId: 7,
      acknowledgedAt: acknowledgedAt,
    );

Future<void> _show(WidgetTester tester, Widget card, {double width = 300}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          // As narrow as the landscape side column on the phone.
          child: SizedBox(width: width, child: card),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('a priority order offers "Rozumím" until confirmed', (
    tester,
  ) async {
    var taps = 0;
    await _show(
      tester,
      MessageCard(message: _order(), onAcknowledge: () => taps++),
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('ack-7')));
    expect(taps, 1);

    final at = DateTime(2026, 10, 26, 9, 5);
    await _show(
      tester,
      MessageCard(
        message: _order(acknowledgedAt: at),
        onAcknowledge: () => taps++,
      ),
    );
    expect(find.byKey(const ValueKey('ack-7')), findsNothing);
    expect(find.text('Potvrzeno 09:05'), findsOneWidget);
  });

  testWidgets('ordinary panel messages need no confirmation', (tester) async {
    await _show(
      tester,
      MessageCard(message: _order(priority: false), onAcknowledge: () {}),
    );
    expect(find.text('Rozumím'), findsNothing);
  });
}
