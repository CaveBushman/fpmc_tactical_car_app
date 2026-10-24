/// A meeting at a mission point at a given time, shared with the group as
/// `SRAZ | <code> | <HH:MM> | <callsign>` and cancelled with
/// `SRAZ ZRUŠEN | <code>`.
class Rendezvous {
  const Rendezvous({required this.code, required this.at, required this.setBy});

  /// Code of the mission point to meet at.
  final String code;
  final DateTime at;
  final String setBy;

  /// Kept on screen until this long after the meeting time.
  static const graceAfter = Duration(minutes: 30);

  bool isOverAt(DateTime now) => now.isAfter(at.add(graceAfter));

  String get clock => _clock(at);

  String get shareText => 'SRAZ | $code | $clock | $setBy';

  static String cancelText(String code) => 'SRAZ ZRUŠEN | $code';

  static final _set = RegExp(r'^SRAZ \| (\S+) \| (\d{1,2}):(\d{2}) \| (.+)$');
  static final _cancel = RegExp(r'^SRAZ ZRUŠEN \| (\S+)$');

  /// A meeting in [text]; the time is read as the next such clock time
  /// around [now] (up to an hour ago counts as today).
  static Rendezvous? parse(String text, {required DateTime now}) {
    final match = _set.firstMatch(text.trim());
    if (match == null) {
      return null;
    }
    final hour = int.parse(match.group(2)!);
    final minute = int.parse(match.group(3)!);
    if (hour > 23 || minute > 59) {
      return null;
    }
    return Rendezvous(
      code: match.group(1)!,
      at: nextOccurrence(hour, minute, now: now),
      setBy: match.group(4)!.trim(),
    );
  }

  /// Code of a cancelled meeting in [text], or null.
  static String? parseCancel(String text) =>
      _cancel.firstMatch(text.trim())?.group(1);

  static DateTime nextOccurrence(
    int hour,
    int minute, {
    required DateTime now,
  }) {
    final today = DateTime(now.year, now.month, now.day, hour, minute);
    if (!today.isBefore(now.subtract(const Duration(hours: 1)))) {
      return today;
    }
    // Next calendar day, not +24 h: daylight saving changes would shift
    // the clock time by an hour.
    return DateTime(now.year, now.month, now.day + 1, hour, minute);
  }

  static String _clock(DateTime at) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(at.hour)}:${two(at.minute)}';
  }
}
