import 'package:flutter_test/flutter_test.dart';
import 'package:tactical_car_app/controllers/tactical_controller.dart';
import 'package:tactical_car_app/models/messaging.dart';
import 'package:tactical_car_app/models/navigation.dart';
import 'package:tactical_car_app/models/track.dart';
import 'package:tactical_car_app/services/location_service.dart';
import 'package:tactical_car_app/services/mesh_packet_repository.dart';
import 'package:tactical_car_app/services/mission_export.dart';

import 'support/fakes.dart';

class _FakeSharer implements MissionSharer {
  final List<(List<ExportFile>, String)> shares = [];

  @override
  Future<void> share(List<ExportFile> files, {required String subject}) async =>
      shares.add((files, subject));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final at = DateTime.utc(2026, 10, 24, 8, 30);

  test('GPX contains escaped waypoints and the trail', () {
    final gpx = buildMissionGpx(
      missionName: 'Mise <EAGLE>',
      exportedAt: at,
      waypoints: const [
        TacticalWaypoint(
          code: 'RALLY-1',
          type: TacticalWaypointType.rally,
          latitude: 50.1,
          longitude: 14.4,
          note: 'most & brod',
          sharedBy: 'VIPER',
        ),
      ],
      track: [
        TrackPoint(latitude: 50.1, longitude: 14.4, altitudeM: 230, at: at),
        TrackPoint(
          latitude: 50.11,
          longitude: 14.41,
          altitudeM: 235,
          at: at.add(const Duration(minutes: 5)),
        ),
      ],
    );

    expect(gpx, startsWith('<?xml version="1.0" encoding="UTF-8"?>'));
    expect(gpx, contains('<name>Mise &lt;EAGLE&gt;</name>'));
    expect(gpx, contains('<wpt lat="50.1000000" lon="14.4000000">'));
    expect(gpx, contains('most &amp; brod'));
    expect(gpx, contains('od VIPER'));
    expect(gpx, contains('<type>RALLY</type>'));
    expect('<trkpt '.allMatches(gpx), hasLength(2));
    expect(gpx, contains('<time>2026-10-24T08:35:00.000Z</time>'));
    expect(gpx.trim(), endsWith('</gpx>'));
  });

  test('GPX without a trail has no empty track', () {
    final gpx = buildMissionGpx(
      missionName: 'x',
      exportedAt: at,
      waypoints: const [],
      track: const [],
    );
    expect(gpx, isNot(contains('<trk>')));
  });

  test('CSV is oldest first, quoted and safe for spreadsheets', () {
    final csv = buildMessagesCsv(
      groups: CommunicationGroup.demoGroups,
      messages: [
        MeshMessage(
          sender: 'VIPER',
          body: '=HYPERLINK("x")',
          sentAt: at.add(const Duration(minutes: 1)),
          groupId: 'bravo',
          viaInternet: true,
        ),
        MeshMessage(
          sender: 'EAGLE',
          body: 'OK; jedeme\na "rychle"',
          sentAt: at,
          groupId: 'alpha',
          delivery: MessageDelivery.delivered,
          priority: true,
        ),
      ],
    );
    final lines = csv.split('\r\n');
    expect(lines.first, startsWith('cas_utc;skupina;od'));
    expect(lines[1], startsWith('2026-10-24T08:30:00.000Z;ALPHA;EAGLE'));
    expect(csv, contains('"OK; jedeme\na ""rychle"""'));
    expect(csv, contains(";delivered;LoRa;ano"));
    expect(csv, contains("'=HYPERLINK"));
    expect(csv, contains(';internet;'));
  });

  group('controller', () {
    late FakeLocationService location;
    late _FakeSharer sharer;
    late TacticalController controller;

    LocationFix fix(double lat, double lon, DateTime time) => LocationFix(
      latitude: lat,
      longitude: lon,
      altitudeM: 240,
      accuracyM: 4,
      timestamp: time,
    );

    setUp(() async {
      location = FakeLocationService();
      sharer = _FakeSharer();
      controller = TacticalController(
        locationService: location,
        meshtasticBleService: FakeBleService(),
        meshPacketRepository: MeshPacketRepository(),
        nativePtt: FakeNativePttBridge(),
        carBridge: FakeCarBridge(),
        missionSharer: sharer,
      );
      await controller.login('operator', 'operator-2026');
    });

    tearDown(() => controller.dispose());

    test('records the trail every 15 m or minute and exports it', () async {
      final start = DateTime.now();
      location.emit(fix(50.0, 14.0, start));
      location.emit(fix(50.00005, 14.0, start.add(const Duration(seconds: 5))));
      location.emit(fix(50.0003, 14.0, start.add(const Duration(seconds: 10))));
      location.emit(fix(50.0003, 14.0, start.add(const Duration(minutes: 2))));
      await pumpEventQueue();

      expect(controller.track, hasLength(3));
      expect(trackLengthKm(controller.track), closeTo(0.033, 0.002));

      await controller.exportMission();
      final (files, subject) = sharer.shares.single;
      expect(subject, startsWith('Mise '));
      expect(files.map((f) => f.name.split('-').first), ['mise', 'zpravy']);
      expect(files.first.mimeType, 'application/gpx+xml');
      expect('<trkpt '.allMatches(files.first.content), hasLength(3));
      expect(files.last.content, contains('cas_utc'));
    });

    test('the trail survives a restart and can be cleared', () async {
      location.emit(fix(50.0, 14.0, DateTime.now()));
      location.emit(fix(50.001, 14.0, DateTime.now()));
      await pumpEventQueue();
      expect(controller.track, hasLength(2));
      await controller.endSession('test');

      await controller.login('operator', 'operator-2026');
      await pumpEventQueue(times: 50);
      expect(controller.track, hasLength(2));

      controller.clearTrack();
      expect(controller.track, isEmpty);
    });
  });
}
