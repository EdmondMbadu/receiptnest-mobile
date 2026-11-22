import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../getting_started/data/onboarding_analytics.dart';
import '../../getting_started/presentation/onboarding_widgets.dart';
import '../data/auth_repository.dart';

class VerifyEmailScreen extends ConsumerStatefulWidget {
  const VerifyEmailScreen({super.key});
  @override
  ConsumerState<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends ConsumerState<VerifyEmailScreen> {
  bool _checking = false;
  bool _sending = false;
  String? _notice;
  String? _error;

  Future<void> _check() async {
    if (_checking || _sending) return;
    setState(() {
      _checking = true;
      _error = null;
      _notice = null;
    });
    try {
      final repository = ref.read(authRepositoryProvider);
      await repository.refreshCurrentUser();
      final user = ref.read(firebaseAuthProvider).currentUser;
      if (!mounted) return;
      if (user?.emailVerified == true) {
        ref.read(onboardingAnalyticsProvider).event('native_email_verified');
        ref.invalidate(authStateProvider);
        context.go('/app/entry');
      } else {
        setState(
          () => _notice =
              'Your email isn’t verified yet. Open the link in your verification email, then try again.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'We couldn’t check just now. Please check your connection and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _resend() async {
    if (_sending || _checking) return;
    setState(() {
      _sending = true;
      _error = null;
      _notice = null;
    });
    try {
      await ref.read(authRepositoryProvider).sendVerificationEmail();
      if (mounted) {
        setState(
          () => _notice =
              'Verification email sent. Check your inbox and spam folder.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'We couldn’t resend the email. Please wait a moment and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = ref.watch(currentUserProvider)?.email;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: OnboardingCanvas(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: OnboardingReveal(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Center(child: OnboardingBrand()),
                      const SizedBox(height: 44),
                      OnboardingPaper(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: cs.primary.withValues(alpha: 0.09),
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                child: Icon(
                                  Icons.mark_email_read_outlined,
                                  color: cs.primary,
                                  size: 32,
                                ),
                              ),
                            ),
                            const SizedBox(height: 28),
                            Text(
                              'One quick check.\nThen your first receipt.',
                              style: Theme.of(context).textTheme.headlineMedium
                                  ?.copyWith(height: 1.15, letterSpacing: -0.8),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Open the verification link we emailed you, then return here to continue.',
                              style: TextStyle(
                                fontSize: 16,
                                height: 1.5,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                            if (email != null) ...[
                              const SizedBox(height: 14),
                              Text(
                                email,
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: cs.primary,
                                ),
                              ),
                            ],
                            const SizedBox(height: 28),
                            FilledButton(
                              onPressed: _checking || _sending ? null : _check,
                              child: Text(
                                _checking
                                    ? 'Checking…'
                                    : 'I’ve verified my email',
                              ),
                            ),
                            const SizedBox(height: 10),
                            TextButton(
                              onPressed: _checking || _sending ? null : _resend,
                              child: Text(
                                _sending
                                    ? 'Sending…'
                                    : 'Resend verification email',
                              ),
                            ),
                            if (_notice != null) ...[
                              const SizedBox(height: 16),
                              OnboardingMessage(message: _notice!),
                            ],
                            if (_error != null) ...[
                              const SizedBox(height: 16),
                              OnboardingMessage(message: _error!, error: true),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      TextButton(
                        onPressed: _checking || _sending
                            ? null
                            : () async {
                                await ref.read(authRepositoryProvider).logout();
                                if (context.mounted) context.go('/login');
                              },
                        child: const Text('Use a different account'),
                      ),
                    ],
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
