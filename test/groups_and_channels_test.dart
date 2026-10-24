import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tactical_car_app/controllers/ptt_controller.dart';
import 'package:tactical_car_app/controllers/tactical_controller.dart';
import 'package:tactical_car_app/models/messaging.dart';
import 'package:tactical_car_app/services/backend_client.dart';
import 'package:tactical_car_app/services/mesh_packet_repository.dart';
import 'package:tactical_car_app/services/meshtastic_ble_service.dart';
import 'package:tactical_car_app/widgets/common_widgets.dart';

import 'support/fakes.dart';
import 'support/mesh_bytes.dart';

BackendClient _backend() => BackendClient(
  baseUrl: 'https://ptt.example.test',
  httpClient: MockClient((request) async {
    if (request.url.path.endsWith('/auth/login')) {
      // Like the server: UTF-8 JSON (no charset needed to decode it).
      return http.Response.bytes(
        utf8.encode(
          jsonEncode({
            'sessionToken': 's',
            'user': {
              'userName': 'operator',
              'displayName': 'OPERATOR',
              'role': 'operator',
              'groups': ['alpha', 'recon'],
            },
            'groups': [
              {
                'id': 'alpha',
                'name': 'ALPHA',
                'channelIndex': 0,
                'pttEnabled': true,
              },
              {
                'id': 'recon',
                'name': 'PRŮZKUM',
                'channelIndex': 4,
                'pttEnabled': false,
                'description': 'jen text',
              },
            ],
          }),
        ),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    return http.Response(
      '{"livekitUrl":"wss://x","room":"ptt-alpha","identity":"operator","token":"t","key":{"id":1,"key":"${'A' * 43}="}}',
      200,
    );
  }),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MeshPacketRepository repository;
  late FakeBleService ble;
  late TacticalController controller;

  setUp(() {
    repository = MeshPacketRepository();
    ble = FakeBleService();
    controller = TacticalController(
      locationService: FakeLocationService(),
      meshtasticBleService: ble,
      meshPacketRepository: repository,
      backend: _backend(),
      voiceTransportFactory: FakeVoiceTransport.new,
      nativePtt: FakeNativePttBridge(),
      carBridge: FakeCarBridge(),
    );
  });

  tearDown(() => controller.dispose());

  void ingest(List<int> bytes) => repository.ingest(
    MeshtasticBlePacket(bytes: bytes, receivedAt: DateTime.now()),
  );

  test('groups, channels and PTT availability come from the backend', () async {
    expect(await controller.login('operator', 'pw'), isNull);
    await pumpEventQueue();

    expect(controller.allowedGroups.map((g) => g.name), ['ALPHA', 'PRŮZKUM']);
    final recon = controller.allowedGroups.last;
    expect(recon.channelIndex, 4);
    expect(recon.transportLabel, 'jen text');
    expect(controller.ptt.status, PttStatus.ready);

    controller.selectGroup(1);
    await pumpEventQueue();
    expect(controller.ptt.status, PttStatus.disabled);
    expect(controller.ptt.channel, 'PRŮZKUM');
    expect(controller.voiceOnline, isFalse);
  });

  test('messages go out on the configured channel slot', () async {
    await controller.login('operator', 'pw');
    await controller.sendMeshText(
      const MeshMessageDraft(text: 'Ahoj', groupId: 'recon'),
    );
    // ToRadio{1: MeshPacket{… 3: channel …}}: channel 4 → bytes 0x18 0x04.
    final written = ble.written.single;
    expect(_containsSequence(written, [0x18, 0x04]), isTrue);
  });

  test('incoming traffic on a configured channel lands in its group', () async {
    await controller.login('operator', 'pw');
    ingest(fromRadioText(from: 0xA1100002, text: 'Na kanalu 4', channel: 4));
    await pumpEventQueue();

    expect(
      controller.messages.firstWhere((m) => m.body == 'Na kanalu 4').groupId,
      'recon',
    );
  });

  test('warns about groups whose channel the T-Beam does not have', () async {
    await controller.login('operator', 'pw');
    expect(controller.channelWarnings, isEmpty, reason: 'no radio config yet');

    ingest(fromRadioMyInfo(0x0BADBEEF));
    ingest(fromRadioChannel(index: 0, role: 1, name: 'ALPHA'));
    ingest(fromRadioChannel(index: 4, role: 0));
    await pumpEventQueue();

    expect(controller.radioChannels.map((c) => c.index), [0, 4]);
    expect(controller.channelWarnings.single, contains('PRŮZKUM'));
    expect(controller.channelWarnings.single, contains('kanál 4'));

    ingest(fromRadioChannel(index: 4, role: 2, name: 'RECON'));
    await pumpEventQueue();
    expect(controller.channelWarnings, isEmpty);
  });

  testWidgets('PTT bar explains a group without PTT', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PttBar(
            status: PttStatus.disabled,
            channel: 'PRŮZKUM',
            userName: 'EAGLE',
            onChanged: (_) {},
          ),
        ),
      ),
    );
    expect(find.textContaining('PRO SKUPINU VYPNUTO'), findsOneWidget);
  });
}

bool _containsSequence(List<int> haystack, List<int> needle) {
  for (var i = 0; i + needle.length <= haystack.length; i++) {
    var match = true;
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) {
        match = false;
        break;
      }
    }
    if (match) {
      return true;
    }
  }
  return false;
}
