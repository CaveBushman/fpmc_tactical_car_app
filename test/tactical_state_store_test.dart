import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tactical_car_app/services/tactical_state_store.dart';

const _node = {
  'nodeNum': 0xA1100001,
  'callSign': 'RAVEN-1',
  'latitude': 50.087451,
  'longitude': 14.420671,
  'isSelf': true,
};

const _message = {
  'sender': 'RAVEN-1',
  'body': 'NA POZICI | MGRS 33U VR 58470 48210',
  'time': '12:34',
  'groupId': 'alpha',
  'delivery': 'notSent',
};

void main() {
  late InMemoryStateKeyStore keys;
  late TacticalStateStore store;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    keys = InMemoryStateKeyStore();
    store = TacticalStateStore(keyStore: keys);
  });

  test('persists and restores tactical state snapshots', () async {
    await store.save(nodes: [_node], messages: [_message], owner: 'operator');

    final restored = await store.load();

    expect(restored, isNotNull);
    expect(restored!.nodes.single['callSign'], 'RAVEN-1');
    expect(restored.messages.single['body'], contains('33U VR 58470 48210'));
    expect(restored.owner, 'operator');
  });

  test('stores state encrypted at rest', () async {
    await store.save(nodes: [_node], messages: [_message]);

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('tactical_state_v2')!;
    expect(raw, isNot(contains('RAVEN')));
    expect(raw, isNot(contains('33U VR')));
    expect(keys.key, hasLength(32));
  });

  test('clear removes data and destroys the key', () async {
    await store.save(nodes: [_node], messages: const []);
    expect(await store.load(), isNotNull);

    await store.clear();

    expect(await store.load(), isNull);
    expect(keys.key, isNull);
  });

  test('unreadable data after key loss is dropped', () async {
    await store.save(nodes: [_node], messages: const []);
    keys.key = List<int>.filled(32, 7);

    expect(await store.load(), isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('tactical_state_v2'), isNull);
  });

  test('migrates legacy plaintext snapshot and removes it', () async {
    SharedPreferences.setMockInitialValues({
      'tactical_state_v1': jsonEncode({
        'version': 1,
        'savedAt': '2026-06-01T10:00:00Z',
        'nodes': [_node],
        'messages': [_message],
      }),
    });

    final restored = await store.load();
    expect(restored!.nodes.single['callSign'], 'RAVEN-1');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('tactical_state_v1'), isNull);
    expect(prefs.getString('tactical_state_v2'), isNot(contains('RAVEN')));
    expect((await store.load())!.messages, hasLength(1));
  });
}
