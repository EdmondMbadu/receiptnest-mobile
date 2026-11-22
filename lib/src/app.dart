import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/routing/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';
import 'features/auth/data/auth_repository.dart';
import 'features/auth/data/welcome_email_delivery.dart';
import 'features/auth/models/user_profile.dart';
import 'features/notifications/data/push_notification_repository.dart';
import 'features/getting_started/data/onboarding_analytics.dart';
import 'features/getting_started/data/native_onboarding_repository.dart';

class ReceiptNestApp extends ConsumerStatefulWidget {
  const ReceiptNestApp({super.key});

  @override
  ConsumerState<ReceiptNestApp> createState() => _ReceiptNestAppState();
}

class _ReceiptNestAppState extends ConsumerState<ReceiptNestApp>
    with WidgetsBindingObserver {
  ProviderSubscription<AsyncValue<User?>>? _welcomeSubscription;
  late final WelcomeEmailDelivery _welcomeDelivery;
  ProviderSubscription<AsyncValue<UserProfile?>>? _profileSubscription;
  String? _lastUnlinkedUserId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _welcomeDelivery = WelcomeEmailDelivery(
      send: ref.read(authRepositoryProvider).sendWelcomeEmailIfNeeded,
    );
    _welcomeSubscription = ref.listenManual<AsyncValue<User?>>(
      authStateProvider,
      (previous, next) {
        final user = next.valueOrNull;
        unawaited(ref.read(onboardingAnalyticsProvider).identify(user?.uid));
        unawaited(
          _welcomeDelivery.sync(
            userId: user?.uid,
            verified: user?.emailVerified ?? false,
          ),
        );
      },
      fireImmediately: true,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_resumeWelcomeEmail());
    });
    final pushRepository = ref.read(pushNotificationRepositoryProvider);

    _profileSubscription = ref.listenManual<AsyncValue<UserProfile?>>(
      currentUserProfileProvider,
      (previous, next) {
        final previousProfile = previous?.valueOrNull;
        final nextProfile = next.valueOrNull;

        if (previousProfile != null && nextProfile == null) {
          _lastUnlinkedUserId = null;
          unawaited(pushRepository.unlinkCurrentDevice(previousProfile.id));
        }

        if (nextProfile == null) {
          return;
        }

        if (_lastUnlinkedUserId == nextProfile.id) {
          return;
        }

        _lastUnlinkedUserId = nextProfile.id;
        unawaited(pushRepository.unlinkCurrentDevice(nextProfile.id));
      },
      fireImmediately: true,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_resumeWelcomeEmail());
  }

  Future<void> _resumeWelcomeEmail() async {
    try {
      final newlyVerified = await ref
          .read(authRepositoryProvider)
          .refreshCurrentUser();
      if (!mounted) return;
      if (newlyVerified) ref.invalidate(authStateProvider);
      final user = ref.read(firebaseAuthProvider).currentUser;
      await _welcomeDelivery.sync(
        userId: user?.uid,
        verified: user?.emailVerified ?? false,
      );
      if (user != null && user.emailVerified && mounted) {
        unawaited(ref.read(nativeOnboardingProvider(user.uid).notifier).sync());
      }
    } catch (_) {
      // Offline resumes must not interrupt the app.
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _welcomeSubscription?.close();
    _profileSubscription?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ref = this.ref;
    final router = ref.watch(appRouterProvider);
    final themeMode = ref.watch(themeModeProvider);
    final user = ref.watch(currentUserProvider);
    // Keep the account's guide alive while navigating between native screens.
    if (user != null && user.emailVerified) {
      ref.watch(nativeOnboardingProvider(user.uid));
    }

    return MaterialApp.router(
      title: 'ReceiptNest AI',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      routerConfig: router,
    );
  }
}
