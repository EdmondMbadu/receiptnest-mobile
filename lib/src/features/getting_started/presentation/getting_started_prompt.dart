import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/native_onboarding_repository.dart';
import 'onboarding_widgets.dart';

class GettingStartedPrompt extends ConsumerWidget {
  const GettingStartedPrompt({
    super.key,
    required this.userId,
    required this.receiptCount,
  });
  final String userId;
  final int receiptCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref
        .watch(nativeOnboardingProvider(userId))
        .valueOrNull
        ?.progress;
    if (receiptCount < 1 ||
        receiptCount >= 3 ||
        progress == null ||
        progress.completed) {
      return const SizedBox.shrink();
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: () => context.push('/app/onboarding'),
        icon: const Icon(Icons.help_outline_rounded, size: 18),
        label: const Text('Continue receipt guide'),
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
