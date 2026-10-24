import 'dart:async';

import '../services/auth_service.dart';
import '../services/backend_client.dart';

/// Keeps a backend session alive: refreshes the token at 75 % of its
/// lifetime, retries after network errors and reports a rejected session.
class SessionKeeper {
  SessionKeeper({
    required this.refresh,
    required this.currentSession,
    required this.onRefreshed,
    required this.onRejected,
    this.minDelay = const Duration(seconds: 30),
    this.retryAfterError = const Duration(minutes: 1),
  });

  final Future<({String token, Duration expiresIn})> Function(String token)
  refresh;

  /// The session the app currently uses (refresh results for an older one
  /// are ignored).
  final AuthSession? Function() currentSession;
  final void Function(AuthSession updated) onRefreshed;
  final Future<void> Function() onRejected;
  final Duration minDelay;
  final Duration retryAfterError;

  Timer? _timer;

  void schedule(AuthSession session, {Duration? after}) {
    _timer?.cancel();
    final lifetime = session.expiresIn;
    if (session.isDemo || lifetime == null) {
      return;
    }
    var delay = after ?? lifetime * 0.75;
    if (delay < minDelay) {
      delay = minDelay;
    }
    _timer = Timer(delay, () => unawaited(_refresh(session)));
  }

  void cancel() => _timer?.cancel();

  Future<void> _refresh(AuthSession session) async {
    final token = session.sessionToken;
    if (token == null || !identical(currentSession(), session)) {
      return;
    }
    try {
      final refreshed = await refresh(token);
      if (!identical(currentSession(), session)) {
        return; // logged out or switched meanwhile
      }
      final updated = session.withToken(refreshed.token, refreshed.expiresIn);
      onRefreshed(updated);
      schedule(updated);
    } on BackendException catch (error) {
      if (!identical(currentSession(), session)) {
        return;
      }
      if (error.statusCode == 401) {
        await onRejected();
      } else {
        // Offline for a moment: the token is still valid, try again soon.
        schedule(session, after: retryAfterError);
      }
    }
  }
}
