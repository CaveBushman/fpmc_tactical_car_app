import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tactical_car_app/app.dart';
import 'package:tactical_car_app/services/backend_client.dart';

import 'support/fakes.dart';

void main() {
  testWidgets('remote PTT shows who is talking and blocks the button', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 932);
    addTearDown(tester.view.reset);

    final transports = <FakeVoiceTransport>[];
    final backend = BackendClient(
      baseUrl: 'https://ptt.example.test',
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/auth/login')) {
          return http.Response(
            '{"sessionToken":"s","user":{"userName":"operator","displayName":"OPERATOR","role":"operator","groups":["alpha"]}}',
            200,
          );
        }
        return http.Response(
          '{"livekitUrl":"wss://x","room":"ptt-alpha","identity":"operator","token":"t","key":{"id":1,"key":"${'A' * 43}="}}',
          200,
        );
      }),
    );

    await tester.pumpWidget(
      TacticalCarApp(
        locationService: FakeLocationService(),
        meshtasticBleService: FakeBleService(),
        backend: backend,
        voiceTransportFactory: () {
          final transport = FakeVoiceTransport();
          transports.add(transport);
          return transport;
        },
      ),
    );
    await tester.enterText(find.byType(TextField).first, 'operator');
    await tester.enterText(find.byType(TextField).at(1), 'whatever');
    await tester.tap(find.text('Přihlásit'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('PTT ALPHA | PŘIPRAVENO | E2EE'),
      findsOneWidget,
    );

    transports.last.remoteFloor('medic', 'take', DateTime.now());
    await tester.pumpAndSettle();

    expect(find.textContaining('MLUVÍ medic'), findsOneWidget);
    expect(find.text('OBSAZENO'), findsOneWidget);
  });
}
