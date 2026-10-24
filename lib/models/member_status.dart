import 'package:flutter/material.dart';

import '../theme.dart';

/// What a team member reports about themselves, sent to the group as
/// `STAV | <callsign> | <label>` so other clients can read it too.
enum MemberStatus {
  ok('OK', Icons.check_circle_outline),
  moving('V POHYBU', Icons.directions_run),
  holding('NA POZICI', Icons.place_outlined),
  wounded('ZRANĚN', Icons.personal_injury_outlined),
  needSupport('POTŘEBUJI PODPORU', Icons.support_outlined),
  outOfAction('MIMO AKCI', Icons.do_not_disturb_on_outlined);

  const MemberStatus(this.label, this.icon);

  final String label;
  final IconData icon;

  /// Wounded / needing support: sent as priority and shown in red.
  bool get urgent =>
      this == MemberStatus.wounded || this == MemberStatus.needSupport;

  Color get color => switch (this) {
    MemberStatus.ok => rangerGreen,
    MemberStatus.moving || MemberStatus.holding => sand,
    MemberStatus.wounded || MemberStatus.needSupport => dangerRed,
    MemberStatus.outOfAction => Colors.grey,
  };

  String shareText(String callSign) => 'STAV | $callSign | $label';

  static final _pattern = RegExp(r'^STAV \| ([^|]+?) \| (.+)$');

  /// Parses a status message; null for anything else.
  static ({String callSign, MemberStatus status})? parse(String text) {
    final match = _pattern.firstMatch(text.trim());
    if (match == null) {
      return null;
    }
    final label = match.group(2)!.trim().toUpperCase();
    for (final status in MemberStatus.values) {
      if (status.label == label) {
        return (callSign: match.group(1)!.trim(), status: status);
      }
    }
    return null;
  }
}

/// Last status heard from a member.
class MemberStatusReport {
  const MemberStatusReport({required this.status, required this.at});

  final MemberStatus status;
  final DateTime at;
}
