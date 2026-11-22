import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/native_onboarding_repository.dart';
import 'onboarding_widgets.dart';

bool shouldShowGettingStartedPrompt({
  required int? receiptCount,
  required bool dismissed,
}) =>
    receiptCount != null && receiptCount >= 0 && receiptCount < 5 && !dismissed;

class GettingStartedPrompt extends ConsumerWidget {
  const GettingStartedPrompt({
    super.key,
    required this.userId,
    required this.onAddReceipt,
    required this.receiptCount,
  });
  final String userId;
  final VoidCallback onAddReceipt;
  final int receiptCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(nativeOnboardingProvider(userId)).valueOrNull;
    if ((state?.receiptCount ?? receiptCount) >= 5 || receiptCount >= 5) {
      return const SizedBox.shrink();
    }
    final complete = state?.progress.completed ?? false;
    final cs = Theme.of(context).colorScheme;
    final title = receiptCount == 0
        ? 'Start with one receipt'
        : receiptCount == 1
        ? 'Your first receipt is in.'
        : receiptCount == 2
        ? 'One more, a little more clarity.'
        : 'You’re getting organized.';
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: OnboardingPaper(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.09),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(
                    receiptCount >= 3
                        ? Icons.task_alt_rounded
                        : Icons.auto_awesome_outlined,
                    color: cs.primary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.4,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        receiptCount == 0
                            ? 'A photo or PDF is all you need. We’ll guide you through it.'
                            : receiptCount < 3
                            ? 'Add another receipt whenever you’re ready. Everything stays together here.'
                            : 'Three receipts is a great start. Your guide is always here if you need it.',
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          height: 1.45,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                FilledButton.icon(
                  onPressed: receiptCount == 0
                      ? () => context.push('/app/onboarding')
                      : onAddReceipt,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: Text(
                    receiptCount == 0
                        ? 'Add my first receipt'
                        : 'Add a receipt',
                  ),
                ),
                TextButton(
                  onPressed: () => context.push(
                    complete ? '/app/onboarding?replay=1' : '/app/onboarding',
                  ),
                  child: Text(complete ? 'Replay guide' : 'Continue guide'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class EmptyReceiptHome extends StatelessWidget {
  const EmptyReceiptHome({
    super.key,
    required this.onAdd,
    required this.onRefresh,
  });
  final VoidCallback onAdd;
  final Future<void> Function() onRefresh;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(28, 24, 28, 100),
                  child: OnboardingReveal(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const ReceiptIllustration(),
                        const SizedBox(height: 24),
                        Text(
                          'Your next receipt\nstarts here.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineLarge
                              ?.copyWith(
                                fontSize: 32,
                                letterSpacing: -1,
                                height: 1.15,
                              ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Take a photo or upload a receipt. We’ll read the details and keep it safe, right here.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16,
                            height: 1.55,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 28),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: onAdd,
                            icon: const Icon(Icons.add_rounded, size: 20),
                            label: const Text('Add my first receipt'),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextButton(
                          onPressed: () => context.push('/app/help'),
                          child: const Text('Help & getting started'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
