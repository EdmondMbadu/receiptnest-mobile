import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:recieptnest_ai/src/features/auth/data/welcome_email_delivery.dart';

void main() {
  test(
    'waits for verified sign-in and sends once across auth refreshes',
    () async {
      final sent = <String>[];
      final delivery = WelcomeEmailDelivery(
        send: (uid) async {
          sent.add(uid);
          return true;
        },
      );
      await delivery.sync(userId: null, verified: false);
      await delivery.sync(userId: 'email-user', verified: false);
      expect(sent, isEmpty);
      await delivery.sync(userId: 'email-user', verified: true);
      await delivery.sync(userId: 'email-user', verified: true);
      expect(sent, ['email-user']);
    },
  );

  test('coalesces concurrent events, while allowing another account', () async {
    final gate = Completer<bool>();
    final sent = <String>[];
    final delivery = WelcomeEmailDelivery(
      send: (uid) {
        sent.add(uid);
        return gate.future;
      },
    );
    final first = delivery.sync(userId: 'google-user', verified: true);
    await delivery.sync(userId: 'google-user', verified: true);
    final second = delivery.sync(userId: 'apple-user', verified: true);
    expect(sent, ['google-user', 'apple-user']);
    gate.complete(true);
    await Future.wait([first, second]);
  });

  test('failed requests remain retryable after a short cooldown', () async {
    var now = DateTime(2026);
    var attempts = 0;
    final delivery = WelcomeEmailDelivery(
      now: () => now,
      send: (_) async => ++attempts > 1,
    );
    await delivery.sync(userId: 'u', verified: true);
    await delivery.sync(userId: 'u', verified: true);
    expect(attempts, 1);
    now = now.add(const Duration(seconds: 31));
    await delivery.sync(userId: 'u', verified: true);
    await delivery.sync(userId: 'u', verified: true);
    expect(attempts, 2);
  });

  test('network exceptions never prevent sign-in and can be retried', () async {
    var now = DateTime(2026);
    var attempts = 0;
    final delivery = WelcomeEmailDelivery(
      now: () => now,
      send: (_) async {
        if (++attempts == 1) throw Exception('offline');
        return true;
      },
    );
    await delivery.sync(userId: 'u', verified: true);
    now = now.add(const Duration(seconds: 31));
    await delivery.sync(userId: 'u', verified: true);
    expect(attempts, 2);
  });
}
