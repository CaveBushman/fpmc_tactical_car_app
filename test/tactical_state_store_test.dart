import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tactical_car_app/services/tactical_state_store.dart';

void main() {
  test('persists and restores tactical state snapshots', () async {
    SharedPreferences.setMockInitialValues({});
    const store = TacticalStateStore(key: 'test_tactical_state');

    await store.save(
      nodes: [
        {
          'nodeNum': 0xA1100001,
          'callSign': 'RAVEN-1',
          'latitude': 50.087451,
          'longitude': 14.420671,
          'isSelf': true,
        },
      ],
      messages: [
        {
          'sender': 'RAVEN-1',
          'body': 'NA POZICI | MGRS 33U VR 58470 48210',
          'time': '12:34',
          'groupId': 'alpha',
          'pending': true,
        },
      ],
    );

    final restored = await store.load();

    expect(restored, isNotNull);
    expect(restored!.nodes.single['callSign'], 'RAVEN-1');
    expect(restored.messages.single['body'], contains('33U VR 58470 48210'));
    expect(restored.messages.single['pending'], isTrue);
  });

  test('clears stored tactical state', () async {
    SharedPreferences.setMockInitialValues({});
    const store = TacticalStateStore(key: 'test_tactical_state_clear');

    await store.save(nodes: const [], messages: const []);
    expect(await store.load(), isNotNull);

    await store.clear();

    expect(await store.load(), isNull);
  });
}
