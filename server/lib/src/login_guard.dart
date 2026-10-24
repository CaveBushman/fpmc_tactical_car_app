/// Locks a user name after repeated failed logins.
class LoginGuard {
  LoginGuard({
    this.maxFailures = 5,
    this.lockout = const Duration(minutes: 5),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final int maxFailures;
  final Duration lockout;
  final DateTime Function() _clock;
  final Map<String, int> _failures = {};
  final Map<String, DateTime> _lockedUntil = {};

  /// Remaining lockout, or null when the user may try.
  Duration? lockedFor(String userName) {
    final until = _lockedUntil[userName];
    if (until == null) {
      return null;
    }
    final remaining = until.difference(_clock());
    if (remaining <= Duration.zero) {
      _lockedUntil.remove(userName);
      return null;
    }
    return remaining;
  }

  void recordFailure(String userName) {
    final failures = (_failures[userName] ?? 0) + 1;
    if (failures >= maxFailures) {
      _failures.remove(userName);
      _lockedUntil[userName] = _clock().add(lockout);
    } else {
      _failures[userName] = failures;
    }
  }

  void recordSuccess(String userName) {
    _failures.remove(userName);
    _lockedUntil.remove(userName);
  }
}
