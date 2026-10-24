import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:tactical_car_app/controllers/battery_watch.dart';
import 'package:tactical_car_app/controllers/tactical_controller.dart';
import 'package:tactical_car_app/models/mesh_node.dart';
import 'package:tactical_car_app/models/navigation.dart';
import 'package:tactical_car_app/services/location_service.dart';
import 'package:tactical_car_app/services/mesh_packet_repository.dart';
import 'package:tactical_car_app/services/meshtastic_ble_service.dart';

import 'support/fakes.dart';
import 'support/mesh_bytes.dart';

TacticalNavSolution _solution(double km) => TacticalNavSolution(
  label: 'T',
  kind: TacticalNavTargetKind.point,
  icon: Icons.place,
  mgrs: '',
  distanceKm: km,
  bearingDeg: 0,
  position: const LatLng(50, 14),
);

MeshNode _node(int num, int? battery, {bool self = false}) => MeshNode(
  nodeNum: num,
  callSign: 'N$num',
  latitude: 50,
  longitude: 14,
  altitudeM: 0,
  lastSeenAt: DateTime.now(),
  batteryPercent: battery,
  isSelf: self,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('ETA uses the speed, never slower than walking', () {
    expect(_solution(1).etaLabelAt(), '12 min');
    expect(_solution(10).etaLabelAt(60), '10 min');
    expect(_solution(85).etaLabelAt(60), '1 h 25 min');
    expect(_solution(120).etaLabelAt(60), '2 h');
    expect(_solution(1).etaLabelAt(2), '12 min'); // below walking pace
    expect(_solution(0.01).etaLabelAt(80), '1 min');
  });

  test('battery warns once below 20 % and re-arms above 30 %', () {
    final watch = BatteryWatch();
    expect(
      watch.update([_node(1, 50), _node(2, null), _node(3, 101)]),
      isEmpty,
    );
    expect(watch.update([_node(1, 20)]).single.nodeNum, 1);
    expect(watch.update([_node(1, 15)]), isEmpty);
    expect(watch.update([_node(1, 25)]), isEmpty); // not re-armed yet
    expect(watch.update([_node(1, 19)]), isEmpty);
    watch.update([_node(1, 35)]); // charged
    expect(watch.update([_node(1, 18)]), hasLength(1));
  });

  test('controller: smoothed speed and low battery notice', () async {
    final location = FakeLocationService();
    final repository = MeshPacketRepository();
    final controller = TacticalController(
      locationService: location,
      meshtasticBleService: FakeBleService(),
      meshPacketRepository: repository,
      nativePtt: FakeNativePttBridge(),
      carBridge: FakeCarBridge(),
    );
    addTearDown(controller.dispose);
    final notices = <String>[];
    controller.notices.listen(notices.add);
    await controller.login('operator', 'operator-2026');
    expect(controller.travelSpeedKmh, 5);

    LocationFix fix(double speed) => LocationFix(
      latitude: 50,
      longitude: 14,
      altitudeM: 0,
      accuracyM: 5,
      timestamp: DateTime.now(),
      headingDeg: 90,
      speedMps: speed,
    );
    location.emit(fix(20)); // 72 km/h
    await pumpEventQueue();
    expect(controller.travelSpeedKmh, closeTo(72, 0.1));
    location.emit(fix(10)); // 36 km/h, smoothed
    await pumpEventQueue();
    expect(controller.travelSpeedKmh, closeTo(72 * 0.7 + 36 * 0.3, 0.1));
    location.emit(fix(0.5)); // stopped: walking pace
    await pumpEventQueue();
    expect(controller.travelSpeedKmh, 5);

    repository.ingest(
      MeshtasticBlePacket(
        bytes: fromRadioTelemetry(from: 0xA1100002, battery: 12),
        receivedAt: DateTime.now(),
      ),
    );
    await pumpEventQueue();
    expect(notices, contains('RAVEN-2: slabá baterie 12 %'));
    expect(controller.missionEvents.first.text, 'RAVEN-2: slabá baterie 12 %');
  });
}
