import '../models/member_status.dart';

/// Last status each member reported, and which urgent ones were already
/// answered here.
class MemberStatusBoard {
  MemberStatusBoard({this.alertLifetime = const Duration(minutes: 30)});

  /// Urgent reports older than this no longer alert.
  final Duration alertLifetime;

  final Map<String, MemberStatusReport> _reports = {};
  final Set<String> _acknowledged = {};

  MemberStatusReport? statusOf(String callSign) => _reports[callSign];

  void report(String callSign, MemberStatus status, DateTime at) =>
      _reports[callSign] = MemberStatusReport(status: status, at: at);

  /// Unanswered urgent reports from others within [alertLifetime], newest
  /// first.
  List<({String callSign, MemberStatusReport report})> urgent({
    required String self,
    required DateTime now,
  }) {
    final cutoff = now.subtract(alertLifetime);
    return [
      for (final MapEntry(key: callSign, value: report) in _reports.entries)
        if (callSign != self &&
            report.status.urgent &&
            report.at.isAfter(cutoff) &&
            !_acknowledged.contains(_key(callSign, report)))
          (callSign: callSign, report: report),
    ]..sort((a, b) => b.report.at.compareTo(a.report.at));
  }

  /// Hides the current report of [callSign] until they report again.
  /// Returns false when there is nothing to acknowledge.
  bool acknowledge(String callSign) {
    final report = _reports[callSign];
    return report != null && _acknowledged.add(_key(callSign, report));
  }

  void clear() {
    _reports.clear();
    _acknowledged.clear();
  }

  static String _key(String callSign, MemberStatusReport report) =>
      '$callSign@${report.at.microsecondsSinceEpoch}';
}
