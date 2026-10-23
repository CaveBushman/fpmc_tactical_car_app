import 'package:flutter_test/flutter_test.dart';
import 'package:tactical_car_app/models/navigation.dart';
import 'package:tactical_car_app/services/meshtastic_packet_decoder.dart';

import 'support/mesh_bytes.dart';

void main() {
  const rally = TacticalWaypoint(
    code: 'RALLY-7',
    type: TacticalWaypointType.rally,
    latitude: 50.086138,
    longitude: 14.414208,
    note: 'u mostu',
  );

  test('share text round-trips', () {
    final parsed = TacticalWaypoint.parseShareText(
      rally.shareText,
      sharedBy: 'RAVEN-2',
    );

    expect(parsed, isNotNull);
    expect(parsed!.code, 'RALLY-7');
    expect(parsed.type, TacticalWaypointType.rally);
    expect(parsed.latitude, 50.086138);
    expect(parsed.longitude, 14.414208);
    expect(parsed.note, 'u mostu');
    expect(parsed.sharedBy, 'RAVEN-2');
  });

  test('ignores ordinary messages and bad coordinates', () {
    expect(TacticalWaypoint.parseShareText('NA POZICI | MGRS x'), isNull);
    expect(
      TacticalWaypoint.parseShareText(
        'WP X | RALLY | MGRS 33U | LAT 95.0 | LON 14.0 | a',
      ),
      isNull,
    );
    expect(
      TacticalWaypoint.parseShareText(
        'WP X | BOGUS | MGRS 33U | LAT 50.0 | LON 14.0 | a',
      ),
      isNull,
    );
  });

  test('danger and medevac shared points are priority', () {
    final parsed = TacticalWaypoint.parseShareText(
      'WP D1 | DANGER | MGRS 33U VR 1 2 | LAT 50.1 | LON 14.4 | mina',
    );
    expect(parsed!.priority, isTrue);
  });

  test('JSON round-trip keeps metadata', () {
    final waypoint = TacticalWaypoint(
      code: 'OBS-9',
      type: TacticalWaypointType.observation,
      latitude: 49.5,
      longitude: 15.5,
      note: 'kopec',
      sharedBy: 'SCOUT-3',
      createdAt: DateTime.utc(2026, 10, 23, 8),
      meshWaypointId: 42,
    );
    final restored = TacticalWaypoint.fromJson(waypoint.toJson());
    expect(restored.code, 'OBS-9');
    expect(restored.type, TacticalWaypointType.observation);
    expect(restored.sharedBy, 'SCOUT-3');
    expect(restored.createdAt, DateTime.utc(2026, 10, 23, 8));
    expect(restored.meshWaypointId, 42);
  });

  test('decodes Meshtastic WAYPOINT_APP', () {
    const decoder = MeshtasticPacketDecoder();
    final event = decoder
        .decodeFromRadio(
          fromRadioWaypoint(
            from: 0x1234,
            id: 77,
            latitude: 49.2,
            longitude: 16.6,
            name: 'Sraz',
            description: 'parkoviste',
            expire: 1900000000,
          ),
        )
        .single;

    expect(event.type, DecodedMeshEventType.waypoint);
    expect(event.waypointId, 77);
    expect(event.latitude, closeTo(49.2, 1e-6));
    expect(event.longitude, closeTo(16.6, 1e-6));
    expect(event.waypointName, 'Sraz');
    expect(event.waypointDescription, 'parkoviste');
    expect(event.waypointExpire, 1900000000);
  });
}
