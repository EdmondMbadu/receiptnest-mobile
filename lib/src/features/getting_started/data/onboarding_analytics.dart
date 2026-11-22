import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final onboardingAnalyticsProvider = Provider<OnboardingAnalytics>(
  (ref) => OnboardingAnalytics(),
);

/// Receipt content, filenames, amounts and email addresses never enter analytics.
class OnboardingAnalytics {
  Future<void> event(
    String name, [
    Map<String, Object> parameters = const {},
  ]) async {
    try {
      await FirebaseAnalytics.instance.logEvent(
        name: name,
        parameters: {'guide_version': 2, ...parameters},
      );
    } catch (_) {
      // Measurement must never interrupt account access or receipt collection.
    }
  }

  Future<void> identify(String? uid) async {
    try {
      await FirebaseAnalytics.instance.setUserId(id: uid);
    } catch (_) {
      // The application also works without an analytics platform channel.
    }
  }
}
