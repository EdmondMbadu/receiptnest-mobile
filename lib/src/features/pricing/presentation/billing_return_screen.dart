import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../auth/data/auth_repository.dart';

const _proHighlights = <String>[
  'Unlimited receipts',
  'Advanced search and filters',
  'Export to CSV and PDF',
  'Spending insights and trends',
  'Priority support',
];

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
    final renewalDate = profile?.subscriptionCurrentPeriodEnd;
    final cancellationAtPeriodEnd =
        profile?.subscriptionCancelAtPeriodEnd == true;
    final renewalLabel = renewalDate == null
        ? null
        : DateFormat('MMM d, y').format(renewalDate.toLocal());
    final emailLabel = (profile?.email ?? '').trim().isEmpty
        ? 'your account email'
        : profile!.email;

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
      title = 'Congratulations, you are now on Pro';
      message =
          'Your payment went through and your workspace has been upgraded.';
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
                if (isCheckout && isSuccess && isPro) ...[
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      color: const Color(0xFF00C805).withValues(alpha: 0.08),
                      border: Border.all(
                        color: const Color(0xFF00C805).withValues(alpha: 0.18),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Pro is active',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: cs.onSurface,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          renewalLabel == null
                              ? 'Your billing status has already synced.'
                              : cancellationAtPeriodEnd
                              ? 'Access stays active until $renewalLabel.'
                              : 'Renews on $renewalLabel.',
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.45,
                            color: cs.onSurface.withValues(alpha: 0.72),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'A payment receipt and confirmation are being emailed to $emailLabel.',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
                      border: Border.all(
                        color: cs.outlineVariant.withValues(alpha: 0.6),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Everything you just unlocked',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: cs.onSurface,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ..._proHighlights.map(
                          (feature) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Padding(
                                  padding: EdgeInsets.only(top: 1),
                                  child: Icon(
                                    Icons.check_circle_rounded,
                                    size: 18,
                                    color: Color(0xFF00C805),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    feature,
                                    style: TextStyle(
                                      fontSize: 14,
                                      height: 1.4,
                                      color: cs.onSurface.withValues(alpha: 0.82),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () => context.go(isCheckout && isSuccess ? '/app/home' : '/app/pricing'),
                  child: Text(
                    isCheckout && isSuccess ? 'Go to dashboard' : (isCheckout ? 'Open pricing' : 'Back to app'),
                  ),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () => context.go('/app/pricing'),
                  child: Text(isCheckout && isSuccess ? 'View plan details' : 'Go to home'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
