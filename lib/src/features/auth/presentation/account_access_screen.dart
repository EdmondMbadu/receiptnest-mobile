import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../../getting_started/data/onboarding_analytics.dart';
import '../../getting_started/data/native_onboarding_repository.dart';
import '../../getting_started/presentation/onboarding_widgets.dart';
import '../data/auth_repository.dart';

class AccountAccessScreen extends ConsumerStatefulWidget {
  const AccountAccessScreen({super.key, required this.signIn});
  final bool signIn;
  @override
  ConsumerState<AccountAccessScreen> createState() =>
      _AccountAccessScreenState();
}

class _AccountAccessScreenState extends ConsumerState<AccountAccessScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _emailOpen = false;
  bool _obscure = true;
  bool _busy = false;
  bool _resetting = false;
  String? _error;
  String? _notice;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  bool get _apple =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  String _message(Object error) {
    if (error is FirebaseAuthException) {
      return switch (error.code) {
        'email-already-in-use' =>
          'This email already has an account. Choose Sign in to continue.',
        'invalid-email' => 'Please check your email address.',
        'weak-password' => 'Choose a password with at least 6 characters.',
        'invalid-credential' || 'wrong-password' || 'user-not-found' =>
          'The email or password does not match. Please try again.',
        'account-exists-with-different-credential' =>
          'An account already uses this email. Sign in with the method you used before.',
        'network-request-failed' =>
          'You seem to be offline. Check your connection and try again.',
        'too-many-requests' => 'Please wait a moment before trying again.',
        _ => 'We couldn’t sign you in. Please try again.',
      };
    }
    if (error is AppAuthException) {
      if (error.code == 'auth/apple-not-configured' ||
          error.code == 'auth/apple-invalid-credential') {
        return 'Apple sign-in is unavailable right now. Please try Google or email.';
      }
      return error.message;
    }
    return 'Something went wrong. Please try again.';
  }

  Future<void> _authenticate(String method) async {
    if (_busy || _resetting) return;
    if (method == 'email' && !(_form.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    final analytics = ref.read(onboardingAnalyticsProvider);
    analytics.event('native_auth_start', {
      'method': method,
      'intent': widget.signIn ? 'sign_in' : 'get_started',
    });
    try {
      final repo = ref.read(authRepositoryProvider);
      switch (method) {
        case 'apple':
          await repo.loginWithApple();
        case 'google':
          await repo.loginWithGoogle();
        default:
          if (widget.signIn) {
            await repo.loginWithEmail(_email.text, _password.text);
          } else {
            await repo.registerWithEmail(
              firstName: _name.text,
              lastName: '',
              email: _email.text,
              password: _password.text,
            );
          }
      }
      analytics.event('native_auth_success', {'method': method});
      if (mounted) {
        final user = ref.read(firebaseAuthProvider).currentUser;
        if (user != null && user.emailVerified) {
          ref.invalidate(nativeOnboardingProvider(user.uid));
        }
        context.go(user?.emailVerified == true ? '/app/entry' : '/verify');
      }
    } catch (error) {
      final cancelled =
          (error is GoogleSignInException &&
              error.code == GoogleSignInExceptionCode.canceled) ||
          (error is AppAuthException && error.code == 'auth/apple-cancelled');
      analytics.event(cancelled ? 'native_auth_cancel' : 'native_auth_error', {
        'method': method,
      });
      if (mounted && !cancelled) {
        if (error is AppAuthException &&
            error.code == 'auth/email-not-verified') {
          context.go('/verify');
        } else {
          setState(() => _error = _message(error));
        }
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reset() async {
    if (_busy || _resetting) return;
    if (!_email.text.trim().contains('@')) {
      setState(
        () => _error = 'Enter your email above so we can send a reset link.',
      );
      return;
    }
    setState(() {
      _resetting = true;
      _error = null;
      _notice = null;
    });
    try {
      await ref.read(authRepositoryProvider).sendPasswordReset(_email.text);
      if (mounted) {
        setState(
          () => _notice =
              'If an account exists for this email, we sent a password reset link. Check your inbox.',
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = _message(e));
    } finally {
      if (mounted) setState(() => _resetting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final disabled = _busy || _resetting;
    return Scaffold(
      body: OnboardingCanvas(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: disabled ? null : () => context.go('/'),
                      tooltip: 'Back',
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                    const Spacer(),
                    const Flexible(child: OnboardingBrand()),
                    const Spacer(),
                    const SizedBox(width: 48),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: OnboardingReveal(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              widget.signIn
                                  ? 'Welcome back.'
                                  : 'Make room for\na little more clarity.',
                              style: Theme.of(context).textTheme.headlineLarge
                                  ?.copyWith(
                                    fontSize: 34,
                                    height: 1.12,
                                    letterSpacing: -1.2,
                                  ),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              widget.signIn
                                  ? 'Sign in to find your receipts, right where you left them.'
                                  : 'Create an account to keep your receipts together and access them across devices.',
                              style: TextStyle(
                                fontSize: 16,
                                height: 1.5,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 28),
                            OnboardingPaper(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (_apple) ...[
                                    AbsorbPointer(
                                      absorbing: disabled,
                                      child: SignInWithAppleButton(
                                        onPressed: disabled
                                            ? () {}
                                            : () => _authenticate('apple'),
                                        height: 52,
                                        borderRadius: BorderRadius.circular(14),
                                        style: dark
                                            ? SignInWithAppleButtonStyle.white
                                            : SignInWithAppleButtonStyle.black,
                                        text: 'Continue with Apple',
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                  ],
                                  SizedBox(
                                    height: 52,
                                    child: OutlinedButton.icon(
                                      onPressed: disabled
                                          ? null
                                          : () => _authenticate('google'),
                                      icon: const GoogleMark(),
                                      label: const Text('Continue with Google'),
                                    ),
                                  ),
                                  const SizedBox(height: 18),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Divider(
                                          color: cs.outlineVariant,
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                        ),
                                        child: Text(
                                          'or',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: cs.onSurfaceVariant,
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        child: Divider(
                                          color: cs.outlineVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 18),
                                  if (!_emailOpen)
                                    OutlinedButton.icon(
                                      onPressed: disabled
                                          ? null
                                          : () {
                                              setState(() => _emailOpen = true);
                                              ref
                                                  .read(
                                                    onboardingAnalyticsProvider,
                                                  )
                                                  .event(
                                                    'native_email_selected',
                                                  );
                                            },
                                      icon: const Icon(
                                        Icons.mail_outline_rounded,
                                        size: 19,
                                      ),
                                      label: const Text('Continue with email'),
                                    ),
                                  AnimatedSize(
                                    duration:
                                        MediaQuery.disableAnimationsOf(context)
                                        ? Duration.zero
                                        : const Duration(milliseconds: 280),
                                    curve: Curves.easeOutCubic,
                                    child: !_emailOpen
                                        ? const SizedBox.shrink()
                                        : AutofillGroup(
                                            child: Form(
                                              key: _form,
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.stretch,
                                                children: [
                                                  if (!widget.signIn) ...[
                                                    TextFormField(
                                                      controller: _name,
                                                      enabled: !disabled,
                                                      textCapitalization:
                                                          TextCapitalization
                                                              .words,
                                                      autofillHints: const [
                                                        AutofillHints.givenName,
                                                      ],
                                                      textInputAction:
                                                          TextInputAction.next,
                                                      decoration:
                                                          const InputDecoration(
                                                            labelText:
                                                                'Name (optional)',
                                                            prefixIcon: Icon(
                                                              Icons
                                                                  .person_outline_rounded,
                                                              size: 20,
                                                            ),
                                                          ),
                                                    ),
                                                    const SizedBox(height: 14),
                                                  ],
                                                  TextFormField(
                                                    controller: _email,
                                                    enabled: !disabled,
                                                    keyboardType: TextInputType
                                                        .emailAddress,
                                                    autofillHints: const [
                                                      AutofillHints.email,
                                                    ],
                                                    textInputAction:
                                                        TextInputAction.next,
                                                    autocorrect: false,
                                                    decoration:
                                                        const InputDecoration(
                                                          labelText: 'Email',
                                                          prefixIcon: Icon(
                                                            Icons
                                                                .mail_outline_rounded,
                                                            size: 20,
                                                          ),
                                                        ),
                                                    validator: (v) =>
                                                        v == null ||
                                                            !RegExp(
                                                              r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                                                            ).hasMatch(v.trim())
                                                        ? 'Enter a valid email address'
                                                        : null,
                                                  ),
                                                  const SizedBox(height: 14),
                                                  TextFormField(
                                                    controller: _password,
                                                    enabled: !disabled,
                                                    obscureText: _obscure,
                                                    autocorrect: false,
                                                    autofillHints: [
                                                      widget.signIn
                                                          ? AutofillHints
                                                                .password
                                                          : AutofillHints
                                                                .newPassword,
                                                    ],
                                                    textInputAction:
                                                        TextInputAction.done,
                                                    onFieldSubmitted: (_) =>
                                                        _authenticate('email'),
                                                    decoration: InputDecoration(
                                                      labelText: 'Password',
                                                      prefixIcon: const Icon(
                                                        Icons
                                                            .lock_outline_rounded,
                                                        size: 20,
                                                      ),
                                                      suffixIcon: IconButton(
                                                        onPressed: () =>
                                                            setState(
                                                              () => _obscure =
                                                                  !_obscure,
                                                            ),
                                                        tooltip: _obscure
                                                            ? 'Show password'
                                                            : 'Hide password',
                                                        icon: Icon(
                                                          _obscure
                                                              ? Icons
                                                                    .visibility_outlined
                                                              : Icons
                                                                    .visibility_off_outlined,
                                                          size: 20,
                                                        ),
                                                      ),
                                                    ),
                                                    validator: (v) =>
                                                        v == null ||
                                                            v.length < 6
                                                        ? 'Use at least 6 characters'
                                                        : null,
                                                  ),
                                                  if (widget.signIn)
                                                    Align(
                                                      alignment:
                                                          Alignment.centerRight,
                                                      child: TextButton(
                                                        onPressed: disabled
                                                            ? null
                                                            : _reset,
                                                        child: Text(
                                                          _resetting
                                                              ? 'Sending link…'
                                                              : 'Forgot password?',
                                                        ),
                                                      ),
                                                    ),
                                                  const SizedBox(height: 18),
                                                  FilledButton(
                                                    onPressed: disabled
                                                        ? null
                                                        : () => _authenticate(
                                                            'email',
                                                          ),
                                                    child: Text(
                                                      widget.signIn
                                                          ? 'Sign in'
                                                          : 'Create account',
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                  ),
                                  if (_busy) ...[
                                    const SizedBox(height: 20),
                                    Semantics(
                                      label: 'Signing in',
                                      liveRegion: true,
                                      child: Center(
                                        child: SizedBox(
                                          width: 22,
                                          height: 22,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                  if (_error != null) ...[
                                    const SizedBox(height: 16),
                                    OnboardingMessage(
                                      message: _error!,
                                      error: true,
                                    ),
                                  ],
                                  if (_notice != null) ...[
                                    const SizedBox(height: 16),
                                    OnboardingMessage(message: _notice!),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(height: 22),
                            TextButton(
                              onPressed: disabled
                                  ? null
                                  : () => context.go(
                                      widget.signIn ? '/register' : '/login',
                                    ),
                              child: Text(
                                widget.signIn
                                    ? 'New to ReceiptNest? Get started'
                                    : 'Already have an account? Sign in',
                              ),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              alignment: WrapAlignment.center,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  'By continuing, you agree to our',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                                TextButton(
                                  onPressed: () => context.push('/terms'),
                                  child: const Text('Terms'),
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
            ],
          ),
        ),
      ),
    );
  }
}

/// Google logo rendered as crisp vector paths, including the signature open G.
class GoogleMark extends StatelessWidget {
  const GoogleMark({super.key});
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 20,
    height: 20,
    child: CustomPaint(painter: _GoogleMarkPainter()),
  );
}

class _GoogleMarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 48, size.height / 48);
    // The four segments use Google's published G artwork coordinates.
    final paths = <(Color, Path)>[
      (
        const Color(0xFF4285F4),
        Path()
          ..moveTo(43.6, 24.5)
          ..cubicTo(43.6, 23.1, 43.5, 21.8, 43.2, 20.5)
          ..lineTo(24, 20.5)
          ..lineTo(24, 28.2)
          ..lineTo(35, 28.2)
          ..cubicTo(34.5, 30.7, 33.1, 32.8, 30.9, 34.2)
          ..lineTo(37.5, 39.3)
          ..cubicTo(41.4, 35.7, 43.6, 30.6, 43.6, 24.5)
          ..close(),
      ),
      (
        const Color(0xFF34A853),
        Path()
          ..moveTo(24, 44)
          ..cubicTo(29.5, 44, 34.1, 42.2, 37.5, 39.3)
          ..lineTo(30.9, 34.2)
          ..cubicTo(29.1, 35.4, 26.8, 36.1, 24, 36.1)
          ..cubicTo(18.7, 36.1, 14.2, 32.5, 12.6, 27.7)
          ..lineTo(5.8, 33)
          ..cubicTo(9.2, 39.5, 16.1, 44, 24, 44)
          ..close(),
      ),
      (
        const Color(0xFFFBBC05),
        Path()
          ..moveTo(12.6, 27.7)
          ..cubicTo(12.2, 26.5, 12, 25.3, 12, 24)
          ..cubicTo(12, 22.7, 12.2, 21.5, 12.6, 20.3)
          ..lineTo(5.8, 15)
          ..cubicTo(4.6, 17.7, 4, 20.8, 4, 24)
          ..cubicTo(4, 27.2, 4.6, 30.3, 5.8, 33)
          ..close(),
      ),
      (
        const Color(0xFFEA4335),
        Path()
          ..moveTo(24, 11.9)
          ..cubicTo(27, 11.9, 29.7, 12.9, 31.8, 15)
          ..lineTo(37.6, 9.2)
          ..cubicTo(34.1, 5.9, 29.5, 4, 24, 4)
          ..cubicTo(16.1, 4, 9.2, 8.5, 5.8, 15)
          ..lineTo(12.6, 20.3)
          ..cubicTo(14.2, 15.5, 18.7, 11.9, 24, 11.9)
          ..close(),
      ),
    ];
    for (final (color, path) in paths) {
      canvas.drawPath(path, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
