/// Keeps auth refreshes from issuing overlapping welcome-email requests.
/// The server owns the permanent, cross-device welcomeEmailSent flag.
class WelcomeEmailDelivery {
  WelcomeEmailDelivery({required this.send, DateTime Function()? now})
    : now = now ?? DateTime.now;

  final Future<bool> Function(String userId) send;
  final DateTime Function() now;
  final _sent = <String>{};
  final _inFlight = <String>{};
  final _lastAttempt = <String, DateTime>{};

  Future<void> sync({required String? userId, required bool verified}) async {
    if (userId == null ||
        !verified ||
        _sent.contains(userId) ||
        _inFlight.contains(userId)) {
      return;
    }
    final lastAttempt = _lastAttempt[userId];
    if (lastAttempt != null &&
        now().difference(lastAttempt) < const Duration(seconds: 30)) {
      return;
    }
    _inFlight.add(userId);
    _lastAttempt[userId] = now();
    try {
      if (await send(userId)) _sent.add(userId);
    } catch (_) {
      // A later sign-in or app resume retries without blocking account access.
    } finally {
      _inFlight.remove(userId);
    }
  }
}
