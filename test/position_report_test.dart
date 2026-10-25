import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tactical_car_app/controllers/tactical_controller.dart';
import 'package:tactical_car_app/models/member_status.dart';
import 'package:tactical_car_app/services/backend_client.dart';
import 'package:tactical_car_app/services/location_service.dart';
import 'package:tactical_car_app/services/mesh_packet_repository.dart';

import 'support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<Map<String, dynamic>> reports;
  late int reportStatus;
  late Duration offset;
  late FakeLocationService location;
  late TacticalController controller;

  setUp(() async {
    reports = [];
    reportStatus = 200;
    offset = Duration.zero;
    location = FakeLocationService();
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
        if (path.endsWith('/report')) {
          expect(request.headers['authorization'], 'Bearer token-1');
          reports.add(jsonDecode(request.body) as Map<String, dynamic>);
          return http.Response(
            reportStatus == 200 ? '{"ok":true}' : '{"error":"x"}',
            reportStatus,
          );
        }
        return http.Response('{"error":"forbidden_group"}', 403);
      }),
    );
    controller = TacticalController(
      locationService: location,
      meshtasticBleService: FakeBleService(),
      meshPacketRepository: MeshPacketRepository(),
      backend: backend,
      voiceTransportFactory: FakeVoiceTransport.new,
      nativePtt: FakeNativePttBridge(),
      carBridge: FakeCarBridge(),
      clock: () => DateTime.now().add(offset),
      agingTick: const Duration(milliseconds: 20),
    );
    addTearDown(controller.dispose);
    await controller.login('operator', 'secret-pass');
  });

  Future<void> fix(double lat) async {
    location.emit(
      LocationFix(
        latitude: lat,
        longitude: 14.4,
        altitudeM: 240.6,
        accuracyM: 6,
        timestamp: DateTime.now(),
      ),
    );
    await pumpEventQueue();
  }

  test('reports at most every 2 minutes, status changes at once', () async {
    await fix(50.0);
    expect(reports, hasLength(1));
    expect(reports.single['lat'], 50.0);
    expect(reports.single['alt'], 241);
    expect(reports.single['accuracy'], 6);
    expect(reports.single, isNot(contains('status')));

    await fix(50.001); // 30 s later: too soon
    expect(reports, hasLength(1));

    await controller.setOwnStatus(MemberStatus.wounded);
    await pumpEventQueue();
    expect(reports, hasLength(2));
    expect(reports.last['status'], 'wounded');

    offset = const Duration(minutes: 3);
    await fix(50.002);
    expect(reports, hasLength(3));
  });

  test('battery saver reports every 5 minutes; failures retry', () async {
    controller.setBatterySaver(true);
    reportStatus = 503;
    await fix(50.0);
    expect(reports, hasLength(1));
    // The failed report does not count: the next fix tries again.
    reportStatus = 200;
    await fix(50.001);
    expect(reports, hasLength(2));

    offset = const Duration(minutes: 3);
    await fix(50.002);
    expect(reports, hasLength(2)); // within 5 minutes
    offset = const Duration(minutes: 6);
    await fix(50.003);
    expect(reports, hasLength(3));
  });

  test('a phone standing still keeps reporting its last fix', () async {
    await fix(50.0);
    expect(reports, hasLength(1));
    // No new fixes (GPS reports movement only), but time passes.
    offset = const Duration(minutes: 2, seconds: 5);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(reports, hasLength(2));
    expect(reports.last['lat'], 50.0);
  });
}
