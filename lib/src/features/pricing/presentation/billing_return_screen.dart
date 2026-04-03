import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/data/auth_repository.dart';

class BillingReturnScreen extends ConsumerWidget {
  const BillingReturnScreen({
    required this.flow,
    this.status,
    super.key,
  });

  final String flow;
  final String? status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final profile = ref.watch(currentUserProfileProvider).valueOrNull;
    final normalizedFlow = flow.toLowerCase();
    final normalizedStatus = (status ?? '').toLowerCase();

    final isCheckout = normalizedFlow == 'checkout';
    final isSuccess = normalizedStatus == 'success';
    final isCancel = normalizedStatus == 'cancel';
    final isPro = profile?.isPro ?? false;

    late final String title;
    late final String message;
    late final Widget leading;

    if (isCheckout && isSuccess && !isPro) {
      title = 'Finalizing your subscription';
      message =
          'Your payment was accepted. ReceiptNest AI is waiting for Stripe webhook confirmation, which usually takes a few seconds.';
      leading = const SizedBox(
        width: 28,
        height: 28,
        child: CircularProgressIndicator(strokeWidth: 3),
      );
    } else if (isCheckout && isSuccess) {
      title = 'Subscription active';
      message =
          'Your Pro plan is active now. You can return to the app and keep going.';
      leading = const Icon(
        Icons.check_circle_rounded,
        size: 32,
        color: Color(0xFF00C805),
      );
    } else if (isCheckout && isCancel) {
      title = 'Checkout canceled';
      message = 'No charge was made. You can return to pricing at any time.';
      leading = Icon(
        Icons.info_outline_rounded,
        size: 32,
        color: cs.primary,
      );
    } else if (normalizedFlow == 'portal') {
      title = 'Returned from billing';
      message =
          'Your billing session is complete. Any subscription updates will appear here automatically.';
      leading = const Icon(
        Icons.receipt_long_rounded,
        size: 32,
        color: Color(0xFF00C805),
      );
    } else {
      title = 'Back in ReceiptNest AI';
      message = 'You can continue where you left off.';
      leading = Icon(
        Icons.open_in_new_rounded,
        size: 32,
        color: cs.primary,
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Billing')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(alignment: Alignment.center, child: leading),
                const SizedBox(height: 18),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.45,
                    color: cs.onSurface.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () => context.go('/app/pricing'),
                  child: Text(isCheckout ? 'Open pricing' : 'Back to app'),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () => context.go('/app/home'),
                  child: const Text('Go to home'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
