import 'package:tactical_car_app/controllers/mission_recorder.dart';
import 'package:tactical_car_app/controllers/session_keeper.dart';
import 'package:tactical_car_app/controllers/sos_coordinator.dart';
import 'package:tactical_car_app/models/navigation.dart';
import 'package:tactical_car_app/models/sos.dart';
import 'package:tactical_car_app/services/auth_service.dart';
import 'package:tactical_car_app/services/backend_client.dart';
import 'package:tactical_car_app/services/location_service.dart';
import 'package:flutter_test/flutter_test.dart';

LocationFix _fix(double lat, DateTime at) => LocationFix(
  latitude: lat,
  longitude: 14.4,
  altitudeM: 200,
  accuracyM: 5,
  timestamp: at,
);

void main() {
  group('MissionRecorder', () {
    final t0 = DateTime(2026, 10, 24, 10);

    test('thins points closer than 15 m within a minute', () {
      final recorder = MissionRecorder(maxPoints: 3);
      expect(recorder.record(_fix(50.0, t0)), isTrue);
      // ~5 m north, 10 s later: skipped.
      expect(
        recorder.record(_fix(50.00005, t0.add(const Duration(seconds: 10)))),
        isFalse,
      );
      // Same spot a minute later: kept.
      expect(
        recorder.record(_fix(50.00005, t0.add(const Duration(minutes: 1)))),
        isTrue,
      );
      // ~110 m away: kept.
      expect(
        recorder.record(_fix(50.001, t0.add(const Duration(minutes: 1)))),
        isTrue,
      );
      expect(recorder.track, hasLength(3));
    });

    test('drops the oldest point over the cap', () {
      final recorder = MissionRecorder(maxPoints: 2);
      for (var i = 0; i < 3; i++) {
        recorder.record(_fix(50.0 + i * 0.01, t0.add(Duration(minutes: i))));
      }
      expect(recorder.track.map((p) => p.latitude), [50.01, 50.02]);
    });
  });

  group('SosCoordinator', () {
    late List<String> sent;
    late List<TacticalWaypoint> points;
    late SosCoordinator sos;

    setUp(() {
      sent = [];
      points = [];
      sos = SosCoordinator(
        repeat: const Duration(milliseconds: 40),
        sendCall: () async => sent.add('call'),
        sendCancel: () async => sent.add('cancel'),
        sendAck: (callSign) async => sent.add('ack $callSign'),
        upsertPoint: points.add,
        removePoint: (code) => points.removeWhere((p) => p.code == code),
        onChanged: () {},
      );
    });

    test('repeats the call until stopped', () async {
      await sos.start();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await sos.stop();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(sent, ['call', 'call', 'call', 'cancel']);
      expect(sos.active, isFalse);
    });

    test('tracks a teammate call, its point, ack and cancel', () async {
      final at = DateTime.now();
      sos.apply(
        SosSignal.parse(
          SosSignal.call(
            callSign: 'ALFA',
            mgrs: '33U VR 00000 00000',
            latitude: 50,
            longitude: 14,
          ),
        )!,
        sender: 'ALFA',
        at: at,
      );
      expect(sos.alerts.single.callSign, 'ALFA');
      expect(points.single.code, 'SOS-ALFA');

      await sos.acknowledge(sos.alerts.single);
      expect(sent, ['ack ALFA']);
      expect(sos.alerts, isEmpty);

      sos.apply(
        SosSignal.parse(SosSignal.cancel('ALFA'))!,
        sender: 'ALFA',
        at: at,
      );
      expect(points, isEmpty);
    });
  });

  group('SessionKeeper', () {
    AuthSession session() => const AuthSession(
      userName: 'alfa',
      displayName: 'Alfa',
      role: 'operator',
      allowedGroupIds: {},
    ).withToken('t1', const Duration(milliseconds: 80));

    test('refreshes at 75 % of the lifetime', () async {
      var current = session();
      final keeper = SessionKeeper(
        refresh: (token) async =>
            (token: '$token+', expiresIn: const Duration(milliseconds: 80)),
        currentSession: () => current,
        onRefreshed: (updated) => current = updated,
        onRejected: () async {},
        minDelay: Duration.zero,
      );
      keeper.schedule(current);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(current.sessionToken, 't1');
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(current.sessionToken, 't1+');
      keeper.cancel();
    });

    test('retries after network errors, then reports rejection', () async {
      final current = session();
      var calls = 0;
      var rejected = false;
      final keeper = SessionKeeper(
        refresh: (token) async {
          calls++;
          throw BackendException(calls == 1 ? 503 : 401, 'x');
        },
        currentSession: () => current,
        onRefreshed: (_) {},
        onRejected: () async => rejected = true,
        minDelay: Duration.zero,
        retryAfterError: const Duration(milliseconds: 50),
      );
      keeper.schedule(current);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(calls, 1);
      expect(rejected, isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(calls, 2);
      expect(rejected, isTrue);
    });

    test('ignores a refresh for a session that is no longer current', () async {
      AuthSession? current = session();
      var calls = 0;
      final keeper = SessionKeeper(
        refresh: (token) async {
          calls++;
          return (token: 'x', expiresIn: const Duration(minutes: 1));
        },
        currentSession: () => current,
        onRefreshed: (_) => fail('stale refresh applied'),
        onRejected: () async {},
        minDelay: Duration.zero,
      );
      keeper.schedule(session());
      current = null; // logged out
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(calls, 0);
    });
  });
}
