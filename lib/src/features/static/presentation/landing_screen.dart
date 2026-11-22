import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../getting_started/data/onboarding_analytics.dart';
import '../../getting_started/presentation/onboarding_widgets.dart';

class LandingScreen extends ConsumerWidget {
  const LandingScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: OnboardingCanvas(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 460),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 28,
                        vertical: 20,
                      ),
                      child: OnboardingReveal(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const OnboardingBrand(),
                            SizedBox(
                              height: constraints.maxHeight < 700 ? 12 : 28,
                            ),
                            ReceiptIllustration(
                              compact: constraints.maxHeight < 700,
                            ),
                            const SizedBox(height: 18),
                            Text(
                              'A little less paper.\nA lot more clarity.',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.headlineLarge
                                  ?.copyWith(
                                    fontSize: constraints.maxHeight < 700
                                        ? 30
                                        : 34,
                                    height: 1.13,
                                    letterSpacing: -1.3,
                                  ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Snap or upload a receipt. We organize the details and keep everything together.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: cs.onSurfaceVariant,
                                fontSize: constraints.maxHeight < 700 ? 15 : 16,
                                height: 1.55,
                              ),
                            ),
                            const SizedBox(height: 28),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton(
                                onPressed: () {
                                  ref
                                      .read(onboardingAnalyticsProvider)
                                      .event('native_get_started');
                                  context.go('/register');
                                },
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 3),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text('Get started'),
                                      SizedBox(width: 10),
                                      Icon(
                                        Icons.arrow_forward_rounded,
                                        size: 19,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton(
                                onPressed: () {
                                  ref
                                      .read(onboardingAnalyticsProvider)
                                      .event('native_sign_in');
                                  context.go('/login');
                                },
                                child: const Text('Sign in'),
                              ),
                            ),
                            const SizedBox(height: 20),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.cloud_done_outlined,
                                  size: 16,
                                  color: cs.primary,
                                ),
                                const SizedBox(width: 7),
                                Flexible(
                                  child: Text(
                                    'Your receipts, wherever you need them.',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ],
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
        ),
      ),
    );
  }
}
