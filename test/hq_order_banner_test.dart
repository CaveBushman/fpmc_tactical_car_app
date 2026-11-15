import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tactical_car_app/app.dart';
import 'package:tactical_car_app/services/backend_client.dart';

import 'support/fakes.dart';

Map<String, Object> _order(
  int id,
  String text, {
  Duration age = Duration.zero,
}) => {
  'id': id,
  'groupId': 'alpha',
  'text': text,
  'priority': true,
  'author': 'VELITEL',
  'at': DateTime.now().subtract(age).toUtc().toIso8601String(),
};

void main() {
  const sizes = {'landscape': Size(856, 384), 'portrait': Size(384, 856)};

  for (final MapEntry(key: orientation, value: size) in sizes.entries) {
    testWidgets('an order waits above the map until "Rozumím", $orientation', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({'settings.fontScale': 1.35});
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.reset);

      final syncs = <Map<String, dynamic>>[];
      var pending = [
        _order(
          7,
          'Okamžitě se stáhněte na RV-1, trasa přes most, '
          'čekejte na další pokyny a hlaste stav',
        ),
        _order(8, 'Druhý rozkaz'),
        // Too old for the banner; it keeps its button in the messages.
        _order(3, 'Včerejší rozkaz', age: const Duration(hours: 13)),
      ];
      final backend = BackendClient(
        baseUrl: 'https://ptt.example.test',
        httpClient: MockClient((request) async {
          final path = request.url.path;
          if (path.endsWith('/auth/login')) {
            return http.Response(
              jsonEncode({
                'sessionToken': 'token-1',
                'expiresInSeconds': 43200,
                'user': {
                  'userName': 'operator',
                  'displayName': 'OPERATOR',
                  'role': 'operator',
                  'groups': ['alpha'],
                },
              }),
              200,
            );
          }
          if (path.endsWith('/messages')) {
            syncs.add(jsonDecode(request.body) as Map<String, dynamic>);
            final body = jsonEncode({'ok': true, 'messages': pending});
            pending = [];
            return http.Response.bytes(utf8.encode(body), 200);
          }
          return http.Response('{"error":"forbidden_group"}', 403);
        }),
      );

      await tester.pumpWidget(
        TacticalCarApp(
          locationService: FakeLocationService(),
          meshtasticBleService: FakeBleService(),
          backend: backend,
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'operator');
      await tester.enterText(find.byType(TextField).at(1), 'secret-pass');
      await tester.tap(find.text('Přihlásit'));
      await tester.pumpAndSettle();

      // No GPS fix: the next tick fetches the orders without a position.
      await tester.pump(const Duration(seconds: 16));
      await tester.pumpAndSettle();
      expect(syncs, isNotEmpty);
      final banner = find.byKey(const ValueKey('hq-order-banner'));
      expect(banner, findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(
        find.descendant(of: banner, matching: find.textContaining('+1 další')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: banner, matching: find.text('Druhý rozkaz')),
        findsOneWidget,
      );

      // Newest first; each "Rozumím" confirms one and shows the next.
      await tester.tap(find.byKey(const ValueKey('hq-order-ack')));
      await tester.pumpAndSettle();
      expect(syncs.last['ackMessageIds'], [8]);
      expect(
        find.descendant(
          of: banner,
          matching: find.textContaining('Okamžitě se stáhněte'),
        ),
        findsOneWidget,
      );

      // Tapping the banner opens the order in the messages.
      await tester.tap(find.byKey(const ValueKey('hq-order-text')));
      await tester.pumpAndSettle();
      final rail = find.byType(NavigationRail);
      expect(
        rail.evaluate().isNotEmpty
            ? tester.widget<NavigationRail>(rail).selectedIndex
            : tester
                  .widget<NavigationBar>(find.byType(NavigationBar))
                  .selectedIndex,
        messagesTabIndex,
      );
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(const ValueKey('hq-order-ack')));
      await tester.pumpAndSettle();
      expect(banner, findsNothing);
      expect(syncs.last['ackMessageIds'], [7]);
      expect(tester.takeException(), isNull);
    });
  }
}
