import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tactical_car_app/app.dart';
import 'package:tactical_car_app/controllers/contact_watch.dart';
import 'package:tactical_car_app/models/mesh_node.dart';
import 'package:tactical_car_app/models/messaging.dart';
import 'package:tactical_car_app/models/search_text.dart';
import 'package:tactical_car_app/screens/messages_page.dart';

import 'support/fakes.dart';

MeshNode _node(int num, {required int minutesAgo, bool self = false}) =>
    MeshNode(
      nodeNum: num,
      callSign: 'N$num',
      latitude: 50,
      longitude: 14,
      altitudeM: 0,
      lastSeenAt: DateTime.now().subtract(Duration(minutes: minutesAgo)),
      isSelf: self,
    );

void main() {
  group('ContactWatch', () {
    test('alerts once when a heard teammate goes LOST', () {
      final watch = ContactWatch();
      expect(
        watch.update([
          _node(1, minutesAgo: 0, self: true),
          _node(2, minutesAgo: 3),
        ]),
        isEmpty,
      );
      expect(watch.update([_node(2, minutesAgo: 10)]), isEmpty); // STALE

      final lost = watch.update([_node(2, minutesAgo: 20)]);
      expect(lost.single.callSign, 'N2');
      expect(watch.alerts.single.nodeNum, 2);

      // Still lost: no second alert.
      expect(watch.update([_node(2, minutesAgo: 25)]), isEmpty);
      expect(watch.alerts, hasLength(1));

      // Heard again: the alert clears.
      watch.update([_node(2, minutesAgo: 0)]);
      expect(watch.alerts, isEmpty);
    });

    test('nodes already lost when first seen never alert', () {
      final watch = ContactWatch();
      watch.update([_node(3, minutesAgo: 60)]);
      expect(watch.update([_node(3, minutesAgo: 61)]), isEmpty);
      expect(watch.alerts, isEmpty);
    });

    test('acknowledge and disappearance remove the alert', () {
      final watch = ContactWatch();
      watch.update([_node(2, minutesAgo: 1), _node(4, minutesAgo: 1)]);
      watch.update([_node(2, minutesAgo: 20), _node(4, minutesAgo: 20)]);
      expect(watch.alerts, hasLength(2));

      watch.acknowledge(2);
      watch.update([_node(4, minutesAgo: 21)]); // node 2 gone, 4 still lost
      expect(watch.alerts.map((a) => a.nodeNum), [4]);
      watch.update(const []);
      expect(watch.alerts, isEmpty);
    });
  });

  group('message search', () {
    test('ignores case and diacritics', () {
      expect(foldForSearch('  ZRANĚN   Příliš  '), 'zranen prilis');
      final message = MeshMessage(
        sender: 'SCOUT-3',
        body: 'STAV | SCOUT-3 | ZRANĚN',
        sentAt: DateTime(2026, 10, 24),
        groupId: 'alpha',
        targetLabel: 'ALPHA',
      );
      expect(message.matchesSearch('zranen'), isTrue);
      expect(message.matchesSearch('scout'), isTrue);
      expect(message.matchesSearch('alpha'), isTrue);
      expect(message.matchesSearch(''), isTrue);
      expect(message.matchesSearch('medevac'), isFalse);
    });

    testWidgets('filters the Messages tab by text and priority', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(430, 1400);
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

      final cards = find.byType(MessageCard);
      final before = cards.evaluate().length;
      expect(before, greaterThan(1));

      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('message-search')),
          matching: find.byType(TextField),
        ),
        'neexistujici-text-xyz',
      );
      await tester.pumpAndSettle();
      expect(cards, findsNothing);
      expect(find.text('Žádná zpráva neodpovídá hledání.'), findsOneWidget);

      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('message-search')),
          matching: find.byType(TextField),
        ),
        '',
      );
      await tester.pumpAndSettle();
      expect(cards.evaluate().length, before);

      await tester.tap(find.byKey(const ValueKey('priority-only')));
      await tester.pumpAndSettle();
      expect(cards.evaluate().length, lessThan(before));
    });
  });
}
