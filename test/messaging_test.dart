import 'package:flutter_test/flutter_test.dart';
import 'package:tactical_car_app/models/messaging.dart';

MeshMessage _message(DateTime sentAt) => MeshMessage(
  sender: 'RAVEN-2',
  body: 'OK',
  sentAt: sentAt,
  groupId: 'alpha',
);

void main() {
  test('round-trips sentAt through JSON', () {
    final sentAt = DateTime.utc(2026, 10, 22, 21, 5);
    final restored = MeshMessage.fromJson(_message(sentAt).toJson());
    expect(restored.sentAt, sentAt);
  });

  test('time label shows date for older messages', () {
    final now = DateTime(2026, 10, 23, 9, 30);
    expect(_message(DateTime(2026, 10, 23, 8, 5)).timeLabel(now), '08:05');
    expect(
      _message(DateTime(2026, 10, 22, 23, 50)).timeLabel(now),
      '22.10. 23:50',
    );
  });

  test('legacy HH:mm snapshot maps to the latest such time', () {
    final restored = MeshMessage.fromJson({
      'sender': 'HQ',
      'body': 'OK',
      'time': '00:01',
      'groupId': 'alpha',
    });
    final now = DateTime.now();
    expect(restored.sentAt.isAfter(now), isFalse);
    expect(now.difference(restored.sentAt), lessThan(const Duration(days: 1)));
    expect(restored.sentAt.hour, 0);
    expect(restored.sentAt.minute, 1);
  });

  test('unparsable legacy time does not crash', () {
    final restored = MeshMessage.fromJson({
      'sender': 'HQ',
      'body': 'OK',
      'time': '--:--',
      'groupId': 'alpha',
    });
    expect(restored.sentAt, DateTime.fromMillisecondsSinceEpoch(0));
  });
}
