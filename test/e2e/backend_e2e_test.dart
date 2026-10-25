// End-to-end: the app's real BackendClient against a running Django
// backend over HTTP. Run through tool/e2e_backend.sh, which starts the
// server and seeds the accounts below; skipped without BACKEND_E2E_URL.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tactical_car_app/services/backend_client.dart';

final _url = Platform.environment['BACKEND_E2E_URL'];

void main() {
  final skip = _url == null
      ? 'set BACKEND_E2E_URL (tool/e2e_backend.sh)'
      : null;
  late BackendClient client;

  setUp(() => client = BackendClient(baseUrl: _url ?? 'http://unused'));
  tearDown(() => client.close());

  Future<BackendException> failure(Future<Object?> call) async {
    try {
      await call;
    } on BackendException catch (error) {
      return error;
    }
    fail('expected a BackendException');
  }

  test('login, refresh and PTT join', () async {
    final login = await client.login(
      'e2e-operator',
      'e2e-operator-pass',
      deviceId: 'a' * 32,
      deviceName: 'Android',
    );
    expect(login.user.userName, 'e2e-operator');
    expect(login.user.displayName, 'OPERÁTOR E2E');
    expect(login.user.groups, {'alpha', 'recon'});
    expect(login.expiresIn, const Duration(hours: 12));
    // Czech names survive the JSON round trip.
    final recon = login.groups.firstWhere((g) => g.id == 'recon');
    expect(recon.name, 'PRŮZKUM');
    expect(recon.channelIndex, 5);
    expect(recon.description, 'Hlídka – sever');

    final refreshed = await client.refresh(login.sessionToken);
    expect(refreshed.token, isNot(isEmpty));
    expect(refreshed.expiresIn, const Duration(hours: 12));

    final ptt = await client.joinPtt(refreshed.token, 'alpha');
    expect(ptt.room, 'ptt-alpha');
    expect(ptt.identity, 'e2e-operator');
    expect(ptt.liveKitUrl, startsWith('wss://'));
    expect(ptt.token.split('.'), hasLength(3));
    expect(ptt.keys.last.bytes, hasLength(32)); // decoded 256-bit key

    // Position report for the commanders' situation page; the panel's
    // messages for the member's groups come back with it.
    final hq = await client.reportPosition(
      refreshed.token,
      latitude: 50.087451,
      longitude: 14.420671,
      at: DateTime.now(),
      altitudeM: 240,
      batteryPercent: 76,
      status: 'holding',
    );
    expect(hq.map((m) => m.text), ['Přesun na RV-1 – ihned']);
    expect(hq.single.priority, isTrue);
    expect(hq.single.author, 'VELITEL E2E');
    final newer = await client.reportPosition(
      refreshed.token,
      latitude: 50.087451,
      longitude: 14.420671,
      at: DateTime.now(),
      batteryPercent: 76,
      sinceMessageId: hq.single.id,
    );
    expect(newer, isEmpty);
    final badReport = await failure(
      client.reportPosition(
        refreshed.token,
        latitude: 95,
        longitude: 14,
        at: DateTime.now(),
      ),
    );
    expect((badReport.statusCode, badReport.code), (400, 'invalid_position'));

    final denied = await failure(client.joinPtt(refreshed.token, 'command'));
    expect((denied.statusCode, denied.code), (403, 'forbidden_group'));
    final silent = await failure(client.joinPtt(refreshed.token, 'recon'));
    expect((silent.statusCode, silent.code), (403, 'ptt_disabled'));
  }, skip: skip);

  test('errors the app shows', () async {
    final wrong = await failure(client.login('e2e-operator', 'nope'));
    expect((wrong.statusCode, wrong.code), (401, 'invalid_credentials'));

    final disabled = await failure(
      client.login('e2e-disabled', 'e2e-disabled-pass'),
    );
    expect((disabled.statusCode, disabled.code), (403, 'account_disabled'));

    // MAX_DEVICES_PER_USER=1: the second phone is refused.
    await client.login('e2e-medic', 'e2e-medic-pass', deviceId: 'b' * 32);
    final secondPhone = await failure(
      client.login('e2e-medic', 'e2e-medic-pass', deviceId: 'c' * 32),
    );
    expect(
      (secondPhone.statusCode, secondPhone.code),
      (403, 'device_not_allowed'),
    );

    final expired = await failure(client.refresh('not-a-token'));
    expect((expired.statusCode, expired.code), (401, 'unauthenticated'));

    for (var i = 0; i < 5; i++) {
      await failure(client.login('e2e-lock', 'wrong-password'));
    }
    final locked = await failure(client.login('e2e-lock', 'e2e-lock-pass'));
    expect((locked.statusCode, locked.code), (429, 'locked'));
    expect(locked.retryAfter!.inSeconds, greaterThan(200));
  }, skip: skip);
}
