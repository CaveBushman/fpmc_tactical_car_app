import 'package:flutter_test/flutter_test.dart';
import 'package:tactical_car_app/controllers/tactical_controller.dart';
import 'package:tactical_car_app/services/location_service.dart';
import 'package:tactical_car_app/services/mesh_packet_repository.dart';
import 'package:tactical_car_app/services/meshtastic_ble_service.dart';
import 'package:tactical_car_app/services/meshtastic_packet_decoder.dart';

import 'support/fakes.dart';
import 'support/mesh_bytes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeLocationService location;
  late FakeBleService ble;
  late MeshPacketRepository repository;
  late TacticalController controller;

  setUp(() async {
    location = FakeLocationService();
    ble = FakeBleService();
    repository = MeshPacketRepository();
    controller = TacticalController(
      locationService: location,
      meshtasticBleService: ble,
      meshPacketRepository: repository,
      nativePtt: FakeNativePttBridge(),
      carBridge: FakeCarBridge(),
    );
    await controller.login('operator', 'operator-2026');
  });

  tearDown(() => controller.dispose());

  LocationFix fix(double lat, double lon) => LocationFix(
    latitude: lat,
    longitude: lon,
    altitudeM: 231,
    accuracyM: 4,
    timestamp: DateTime.now(),
  );

  /// Positions written to the radio, decoded back.
  List<DecodedMeshEvent> positions() => [
    for (final frame in ble.written)
      ...const MeshtasticPacketDecoder()
          .decodeFromRadio([0x12, ...frame.sublist(1)])
          .where((e) => e.type == DecodedMeshEventType.position),
  ];

  test('sends the phone position into the mesh, throttled', () async {
    location.emit(fix(50.0, 14.0));
    await pumpEventQueue();
    expect(positions(), hasLength(1));
    expect(positions().single.latitude, closeTo(50.0, 1e-7));
    expect(positions().single.altitude, 231);

    location.emit(fix(50.0001, 14.0)); // ~11 m, within the minute
    await pumpEventQueue();
    expect(positions(), hasLength(1));

    location.emit(fix(50.001, 14.0)); // ~110 m
    await pumpEventQueue();
    expect(positions(), hasLength(2));
  });

  test('the handshake re-announces the position at once', () async {
    location.emit(fix(50.0, 14.0));
    await pumpEventQueue();
    repository.ingest(
      MeshtasticBlePacket(bytes: pbVarint(7, 1), receivedAt: DateTime.now()),
    );
    await pumpEventQueue();
    expect(positions(), hasLength(2));
  });

  test('can be switched off and needs a connected radio', () async {
    controller.setSharePositionToMesh(false);
    location.emit(fix(50.0, 14.0));
    await pumpEventQueue();
    expect(positions(), isEmpty);

    controller.setSharePositionToMesh(true); // sends the last fix
    await pumpEventQueue();
    expect(positions(), hasLength(1));

    ble.connected = false;
    location.emit(fix(50.01, 14.0));
    await pumpEventQueue();
    expect(positions(), hasLength(1));
  });
}
