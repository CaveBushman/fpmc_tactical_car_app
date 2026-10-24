import 'package:flutter_test/flutter_test.dart';
import 'package:tactical_car_app/controllers/mission_log.dart';
import 'package:tactical_car_app/controllers/unread_counter.dart';
import 'package:tactical_car_app/models/mission_event.dart';

MissionEvent _event(int minute) => MissionEvent(
  at: DateTime(2026, 10, 24, 12, minute),
  kind: MissionEventKind.waypoint,
  text: 'e$minute',
);

void main() {
  test('mission log keeps the newest within its capacity', () {
    final log = MissionLog(capacity: 3);
    for (var i = 0; i < 5; i++) {
      log.add(_event(i));
    }
    expect(log.events.map((e) => e.text), ['e4', 'e3', 'e2']);
  });

  test('restored events go after the ones logged since login', () {
    final log = MissionLog(capacity: 3)..add(_event(10));
    log.appendRestored([_event(2), _event(1), _event(0)]);
    expect(log.events.map((e) => e.text), ['e10', 'e2', 'e1']);
    expect(log.toJson().first['text'], 'e10');
    log.clear();
    expect(log.events, isEmpty);
  });

  test('unread counter per group', () {
    final unread = UnreadCounter()
      ..add('alpha')
      ..add('alpha')
      ..add('med');
    expect(unread.countIn('alpha'), 2);
    expect(unread.total(['alpha', 'med', 'bravo']), 3);
    expect(unread.total(['med']), 1);
    expect(unread.markRead('alpha'), isTrue);
    expect(unread.markRead('alpha'), isFalse);
    expect(unread.total(['alpha', 'med']), 1);
  });
}
