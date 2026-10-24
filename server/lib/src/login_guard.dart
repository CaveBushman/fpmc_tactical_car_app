/// Locks a key (user name + client address) after repeated failed logins.
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

/// Sliding-window limit of attempts per key (client IP), so a single
/// source cannot hammer the login endpoint or lock out many accounts.
class RateLimiter {
  RateLimiter({
    this.maxAttempts = 30,
    this.window = const Duration(minutes: 10),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final int maxAttempts;
  final Duration window;
  final DateTime Function() _clock;
  final Map<String, List<DateTime>> _hits = {};

  /// Records an attempt; returns false when [key] is over the limit.
  bool allow(String key) {
    final now = _clock();
    final cutoff = now.subtract(window);
    final hits = _hits.putIfAbsent(key, () => [])
      ..removeWhere((at) => !at.isAfter(cutoff));
    if (hits.length >= maxAttempts) {
      return false;
    }
    hits.add(now);
    if (_hits.length > 10000) {
      _hits.removeWhere((_, value) => value.every((at) => !at.isAfter(cutoff)));
    }
    return true;
  }

  /// Time until [key] may try again (zero when allowed now).
  Duration retryAfter(String key) {
    final hits = _hits[key];
    if (hits == null || hits.length < maxAttempts) {
      return Duration.zero;
    }
    return hits.first.add(window).difference(_clock());
  }
}
