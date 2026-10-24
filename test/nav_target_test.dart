import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:tactical_car_app/controllers/tactical_controller.dart';
import 'package:tactical_car_app/models/navigation.dart';
import 'package:tactical_car_app/services/location_service.dart';
import 'package:tactical_car_app/services/mesh_packet_repository.dart';

import 'support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeLocationService location;
  late FakeCarBridge car;
  late TacticalController controller;
  late List<String> notices;

  LocationFix at(double lat) => LocationFix(
    latitude: lat,
    longitude: 15.5,
    altitudeM: 300,
    accuracyM: 5,
    timestamp: DateTime.now(),
  );

  setUp(() async {
    location = FakeLocationService();
    car = FakeCarBridge();
    controller = TacticalController(
      locationService: location,
      meshtasticBleService: FakeBleService(),
      meshPacketRepository: MeshPacketRepository(),
      nativePtt: FakeNativePttBridge(),
      carBridge: car,
    );
    notices = [];
    controller.notices.listen(notices.add);
    await controller.login('operator', 'operator-2026');
    location.emit(at(49.0));
    await pumpEventQueue();
  });

  tearDown(() => controller.dispose());

  TacticalWaypoint addRally() => controller.addWaypoint(
    type: TacticalWaypointType.rally,
    latitude: 49.02,
    longitude: 15.5,
    code: 'RV',
  );

  test('a chosen waypoint is followed until reached', () async {
    addRally();
    controller.navigateTo(const NavTarget.waypoint('RV'));
    final solution = controller.navTarget!;
    expect(solution.label, 'RV');
    expect(solution.distanceKm, closeTo(2.22, 0.02));
    expect(solution.bearingDeg, closeTo(0, 1));
    expect(car.targets.first.title, 'RV');
    expect(car.targets.first.priority, isTrue);

    location.emit(at(49.01));
    await pumpEventQueue();
    expect(controller.navTarget!.distanceKm, closeTo(1.11, 0.02));

    location.emit(at(49.0197)); // ~33 m short
    await pumpEventQueue();
    expect(controller.navTarget, isNull);
    expect(notices, contains('Cíl RV dosažen.'));
  });

  test('navigation ends when the point is deleted', () async {
    final rally = addRally();
    controller.navigateTo(const NavTarget.waypoint('RV'));
    controller.removeWaypoint(rally);
    await pumpEventQueue();
    expect(controller.navTarget, isNull);
    expect(notices, contains('Cíl navigace už neexistuje.'));
  });

  test('a teammate target follows the teammate', () async {
    final peer = controller.peers.first;
    controller.navigateTo(NavTarget.node(peer.nodeNum));
    expect(controller.navTarget!.label, peer.callSign);
    expect(controller.navTarget!.position, peer.latLng);
  });

  test('a free map point can be the target and is cleared on logout', () async {
    controller.navigateTo(const NavTarget.point(LatLng(49.0, 15.6)));
    expect(controller.navTarget!.label, startsWith('BOD '));
    expect(controller.navTarget!.bearingDeg, closeTo(90, 1));

    controller.clearNavTarget();
    expect(controller.navTarget, isNull);

    controller.navigateTo(const NavTarget.point(LatLng(49.0, 15.6)));
    await controller.logout();
    await controller.login('operator', 'operator-2026');
    expect(controller.navTarget, isNull);
  });
}
