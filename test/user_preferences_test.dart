import 'package:flutter_test/flutter_test.dart';
import 'package:tactical_car_app/controllers/member_status_board.dart';
import 'package:tactical_car_app/controllers/user_preferences.dart';
import 'package:tactical_car_app/models/member_status.dart';
import 'package:tactical_car_app/services/settings_store.dart';

void main() {
  test('preferences are saved on change and read back by load', () async {
    final first = UserPreferences(const SettingsStore());
    first
      ..fontScale = 1.2
      ..nightModeAuto = true
      ..mgrsGrid = false
      ..batterySaver = true
      ..quickMessages = ['A', 'B'];
    await pumpEventQueue();

    final second = UserPreferences(const SettingsStore());
    await second.load();
    expect(second.fontScale, 1.2);
    expect(second.nightModeAuto, isTrue);
    expect(second.mgrsGrid, isFalse);
    expect(second.batterySaver, isTrue);
    expect(second.quickMessages, ['A', 'B']);
    expect(second.hideSystemBars, isTrue); // untouched default

    second.reset();
    expect(second.fontScale, 1.0);
    expect(second.mgrsGrid, isTrue);
    expect(second.quickMessages, SettingsStore.defaultQuickMessages);
  });

  test('font scale from storage is clamped', () async {
    await const SettingsStore().setFontScale(3);
    final prefs = UserPreferences(const SettingsStore());
    await prefs.load();
    expect(prefs.fontScale, 1.35);
  });

  test('status board: urgent reports alert until acknowledged', () {
    final board = MemberStatusBoard();
    final now = DateTime(2026, 10, 24, 13);
    board
      ..report('ME', MemberStatus.wounded, now)
      ..report('A', MemberStatus.ok, now)
      ..report(
        'B',
        MemberStatus.wounded,
        now.subtract(const Duration(minutes: 5)),
      )
      ..report('C', MemberStatus.needSupport, now)
      ..report(
        'D',
        MemberStatus.wounded,
        now.subtract(const Duration(hours: 1)),
      );

    expect(board.urgent(self: 'ME', now: now).map((a) => a.callSign), [
      'C',
      'B',
    ]);

    expect(board.acknowledge('C'), isTrue);
    expect(board.acknowledge('C'), isFalse);
    expect(board.urgent(self: 'ME', now: now).map((a) => a.callSign), ['B']);

    board.report(
      'C',
      MemberStatus.wounded,
      now.add(const Duration(minutes: 1)),
    );
    expect(board.urgent(self: 'ME', now: now).map((a) => a.callSign), [
      'C',
      'B',
    ]);

    board.clear();
    expect(board.statusOf('B'), isNull);
  });
}
